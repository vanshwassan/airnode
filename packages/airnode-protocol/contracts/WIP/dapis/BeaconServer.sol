// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../whitelist/WhitelistWithManager.sol";
import "../AirnodeUser.sol";
import "./interfaces/IBeaconServer.sol";

/// @title Contract that serves beacons using Airnode RRP and PSP
/// @notice A beacon is a live data point associated with a beacon ID, which is
/// derived from a template ID and additional parameters. This is suitable
/// where the more recent data point is always more favorable, e.g., in the
/// context of an asset price data feed. Another definition of beacons are
/// one-Airnode data feeds that can be used individually or combined to build
/// decentralized data feeds.
/// @dev This contract casts the reported data point to `int224`. If this is
/// a problem (because the reported data may not fit into 224 bits or it is of
/// a completely different type such as `bytes32`), do not use this contract
/// and implement a customized version instead.
/// The contract casts the timestamps to `uint32`, which means it will not work
/// work past-2106 in the current form. If this is an issue, consider casting
/// the timestamps to a larger type.
contract BeaconServer is WhitelistWithManager, AirnodeUser, IBeaconServer {
    struct Beacon {
        int224 value;
        uint32 timestamp;
    }

    /// @notice Description of the unlimited reader role
    string public constant override UNLIMITED_READER_ROLE_DESCRIPTION =
        "Unlimited reader";

    /// @notice Unlimited reader role
    bytes32 public immutable override unlimitedReaderRole;

    /// @notice Description of the update requester
    string public constant override UPDATE_REQUESTER_ROLE_DESCRIPTION =
        "Update requester";

    bytes32 private constant UPDATE_REQUESTER_ROLE_DESCRIPTION_HASH =
        keccak256(abi.encodePacked(UPDATE_REQUESTER_ROLE_DESCRIPTION));

    mapping(bytes32 => Beacon) private beacons;
    mapping(bytes32 => bytes32) private requestIdToBeaconId;

    /// @param _accessControlRegistry AccessControlRegistry contract address
    /// @param _adminRoleDescription Admin role description
    /// @param _manager Manager address
    /// @param _airnodeProtocol Airnode protocol contract address
    constructor(
        address _accessControlRegistry,
        string memory _adminRoleDescription,
        address _manager,
        address _airnodeProtocol
    )
        WhitelistWithManager(
            _accessControlRegistry,
            _adminRoleDescription,
            _manager
        )
        AirnodeUser(_airnodeProtocol)
    {
        unlimitedReaderRole = _deriveRole(
            _deriveAdminRole(manager),
            keccak256(abi.encodePacked(UNLIMITED_READER_ROLE_DESCRIPTION))
        );
    }

    /// @notice Called to request a beacon to be updated
    /// @dev There are two requirements for this method to be called: (1) The
    /// sponsor must call `setSponsorshipStatus()` of AirnodeProtocol to
    /// sponsor this BeaconServer contract, (2) The sponsor must call
    /// `setUpdatePermissionStatus()` of this BeaconServer contract to give
    /// request update permission to the user of this method.
    /// The template and additional parameters used here must specify a single
    /// point of data of type `int256` and an additional timestamp of type
    /// `uint256` to be returned because this is what `fulfill()` expects.
    /// This point of data must be castable to `int224` and the timestamp must
    /// be castable to `uint32`.
    /// @param templateId Template ID of the beacon to be updated
    /// @param reporter Reporter address
    /// @param sponsor Sponsor whose wallet will be used to fulfill this
    /// request
    /// @param sponsorWallet Sponsor wallet that will be used to fulfill this
    /// request
    /// @param parameters Parameters provided by the requester in addition to
    /// the parameters in the template
    function requestBeaconUpdate(
        bytes32 templateId,
        address reporter,
        address sponsor,
        address sponsorWallet,
        bytes calldata parameters
    ) external override {
        require(
            requesterIsUpdateRequesterOrIsSponsor(sponsor, msg.sender),
            "Sender not permitted"
        );
        bytes32 beaconId = deriveBeaconId(templateId, parameters);
        bytes32 requestId = IAirnodeProtocol(airnodeProtocol).makeRequest(
            templateId,
            reporter,
            sponsor,
            sponsorWallet,
            address(this),
            this.fulfillRrp.selector,
            parameters
        );
        requestIdToBeaconId[requestId] = beaconId;
        emit RequestedBeaconUpdate(
            beaconId,
            sponsor,
            msg.sender,
            requestId,
            templateId,
            sponsorWallet,
            parameters
        );
    }

    /// @notice Called by the Airnode protocol to fulfill the request
    /// @dev It is assumed that the fulfillment will be made with a single
    /// point of data of type `int256` and an additional timestamp of type
    /// `uint256`
    /// @param requestId ID of the request being fulfilled
    /// @param data Fulfillment data (a single `int256` and an additional
    /// timestamp of type `uint256` encoded as `bytes`)
    function fulfillRrp(bytes32 requestId, bytes calldata data)
        external
        override
        onlyAirnodeProtocol
    {
        bytes32 beaconId = requestIdToBeaconId[requestId];
        require(beaconId != bytes32(0), "No such request made");
        delete requestIdToBeaconId[requestId];
        (int256 decodedData, uint256 decodedTimestamp) = decodeAndValidateData(
            beaconId,
            data
        );
        beacons[beaconId] = Beacon({
            value: int224(decodedData),
            timestamp: uint32(decodedTimestamp)
        });
        emit UpdatedBeaconWithRrp(
            beaconId,
            requestId,
            int224(decodedData),
            uint32(decodedTimestamp)
        );
    }

    /// @notice Called by the Airnode protocol to fulfill the subscription
    /// @dev It is assumed that the fulfillment will be made with a single
    /// point of data of type `int256` and an additional timestamp of type
    /// `uint256`
    /// @param subscriptionId ID of the subscription being fulfilled
    /// @param data Fulfillment data (a single `int256` and an additional
    /// timestamp of type `uint256` encoded as `bytes`)
    function fulfillPsp(bytes32 subscriptionId, bytes calldata data)
        external
        override
        onlyAirnodeProtocol
    {
        (
            bytes32 templateId,
            ,
            ,
            ,
            ,
            bytes memory parameters
        ) = IAirnodeProtocol(airnodeProtocol).subscriptions(subscriptionId);
        bytes32 beaconId = deriveBeaconId(templateId, parameters);
        (int256 decodedData, uint256 decodedTimestamp) = decodeAndValidateData(
            beaconId,
            data
        );
        beacons[beaconId] = Beacon({
            value: int224(decodedData),
            timestamp: uint32(decodedTimestamp)
        });
        emit UpdatedBeaconWithPsp(
            beaconId,
            subscriptionId,
            int224(decodedData),
            uint32(decodedTimestamp)
        );
    }

    /// @notice Called by the fulfillment functions to decode and validate
    /// fulfillment data
    /// @param beaconId Beacon ID
    /// @param data Fulfillment data (a single `int256` and an additional
    /// timestamp of type `uint256` encoded as `bytes`)
    /// @return decodedData Decoded value that will update the beacon
    /// @return decodedTimestamp Decoded timestamp that will update the beacon
    function decodeAndValidateData(bytes32 beaconId, bytes calldata data)
        private
        view
        returns (int256 decodedData, uint256 decodedTimestamp)
    {
        require(data.length == 64, "Incorrect data length");
        (decodedData, decodedTimestamp) = abi.decode(data, (int256, uint256));
        require(
            decodedData >= type(int224).min && decodedData <= type(int224).max,
            "Value typecasting error"
        );
        require(
            decodedTimestamp <= type(uint32).max,
            "Timestamp typecasting error"
        );
        require(
            decodedTimestamp > beacons[beaconId].timestamp,
            "Fulfillment older than beacon"
        );
        require(
            decodedTimestamp + 1 hours > block.timestamp,
            "Fulfillment stale"
        );
        require(
            decodedTimestamp - 1 hours < block.timestamp,
            "Fulfillment from future"
        );
    }

    /// @notice Called to read the beacon
    /// @dev The sender must be whitelisted.
    /// If the `timestamp` of a beacon is zero, this means that it was never
    /// written to before, and the zero value in the `value` field is not
    /// valid. In general, make sure to check if the timestamp of the beacon is
    /// fresh enough, and definitely disregard beacons with zero `timestamp`.
    /// @param beaconId ID of the beacon that will be returned
    /// @return value Beacon value
    /// @return timestamp Beacon timestamp
    function readBeacon(bytes32 beaconId)
        external
        view
        override
        returns (int224 value, uint32 timestamp)
    {
        require(
            readerCanReadBeacon(beaconId, msg.sender),
            "Sender not whitelisted"
        );
        Beacon storage beacon = beacons[beaconId];
        return (beacon.value, beacon.timestamp);
    }

    /// @notice Called to check if a reader is whitelisted to read the beacon
    /// @param beaconId Beacon ID
    /// @param reader Reader address
    /// @return isWhitelisted If the reader is whitelisted
    function readerCanReadBeacon(bytes32 beaconId, address reader)
        public
        view
        override
        returns (bool)
    {
        return
            userIsWhitelisted(beaconId, reader) ||
            userIsUnlimitedReader(reader);
    }

    /// @notice Called to get the detailed whitelist status of the reader for
    /// the beacon
    /// @param beaconId Beacon ID
    /// @param reader Reader address
    /// @return expirationTimestamp Timestamp at which the whitelisting of the
    /// reader will expire
    /// @return indefiniteWhitelistCount Number of times `reader` was
    /// whitelisted indefinitely for `templateId`
    function beaconIdToReaderToWhitelistStatus(bytes32 beaconId, address reader)
        external
        view
        override
        returns (uint64 expirationTimestamp, uint192 indefiniteWhitelistCount)
    {
        WhitelistStatus
            storage whitelistStatus = serviceIdToUserToWhitelistStatus[
                beaconId
            ][reader];
        expirationTimestamp = whitelistStatus.expirationTimestamp;
        indefiniteWhitelistCount = whitelistStatus.indefiniteWhitelistCount;
    }

    /// @notice Returns if an account has indefinitely whitelisted the reader
    /// for the beacon
    /// @param beaconId Beacon ID
    /// @param reader Reader address
    /// @param setter Address of the account that has potentially whitelisted
    /// the reader for the beacon indefinitely
    /// @return indefiniteWhitelistStatus If `setter` has indefinitely
    /// whitelisted reader for the beacon
    function beaconIdToReaderToSetterToIndefiniteWhitelistStatus(
        bytes32 beaconId,
        address reader,
        address setter
    ) external view override returns (bool indefiniteWhitelistStatus) {
        indefiniteWhitelistStatus = serviceIdToUserToSetterToIndefiniteWhitelistStatus[
            beaconId
        ][reader][setter];
    }

    /// @notice Derives the beacon ID from the respective template ID and
    /// additional parameters
    /// @param templateId Template ID
    /// @param parameters Parameters provided by the requester in addition to
    /// the parameters in the template
    /// @return beaconId Beacon ID
    function deriveBeaconId(bytes32 templateId, bytes memory parameters)
        public
        pure
        override
        returns (bytes32 beaconId)
    {
        beaconId = keccak256(abi.encodePacked(templateId, parameters));
    }

    /// @notice Returns if the user has the role unlimited reader
    /// @dev An unlimited reader can read all resources. `address(0)` is
    /// treated as an unlimited reader to provide an easy way for off-chain
    /// agents to read beacon values without having to resort to logs.
    /// @param user User address
    /// @return If the user is unlimited reader
    function userIsUnlimitedReader(address user) private view returns (bool) {
        return
            IAccessControlRegistry(accessControlRegistry).hasRole(
                unlimitedReaderRole,
                user
            ) || user == address(0);
    }

    /// @notice Called to get the update requester role for a specific sponsor
    /// for this BeaconServer contract
    /// @param sponsor Sponsor address
    /// @return updateRequesterRole Update requester role
    function deriveUpdateRequesterRole(address sponsor)
        public
        view
        override
        returns (bytes32 updateRequesterRole)
    {
        updateRequesterRole = _deriveRole(
            _deriveAdminRole(sponsor),
            UPDATE_REQUESTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @notice Called to check if the requester is sponsored by the sponsor or
    /// is the sponsor
    /// @param sponsor Sponsor address
    /// @param requester Requester address
    /// @return If requester is sponsored by the sponsor or is the sponsor
    function requesterIsUpdateRequesterOrIsSponsor(
        address sponsor,
        address requester
    ) public view override returns (bool) {
        return
            sponsor == requester ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                deriveUpdateRequesterRole(sponsor),
                requester
            );
    }
}
