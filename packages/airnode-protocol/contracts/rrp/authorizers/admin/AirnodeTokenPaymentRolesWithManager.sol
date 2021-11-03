// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../../access-control-registry/RoleDeriver.sol";
import "../../../access-control-registry/AccessControlClient.sol";
import "../../../access-control-registry/interfaces/IAccessControlRegistry.sol";
import "./interfaces/IAirnodeTokenPaymentRolesWithManager.sol";

/// @title Contract that implements generic AccessControlRegistry roles for
/// the AirnodePaymentLock contract
contract AirnodeTokenPaymentRolesWithManager is
    RoleDeriver,
    AccessControlClient,
    IAirnodeTokenPaymentRolesWithManager
{
    // There are 5 roles implemented in this contract:
    // Root
    // └── (1) Admin (can grant and revoke the roles below)
    //     ├── (2) Airnode authorizer registry setter
    //     ├── (3) Airnode fee registry setter
    //     ├── (4) Payment token price setter (Oracle)
    //     ├── (5) Airnode to maximum whitelist duration setter
    //     ├── (6) Airnode to payment destination setter
    // Their IDs are derived from the descriptions below. Refer to
    // AccessControlRegistry for more information.
    string public override adminRoleDescription;
    string
        public constant
        override AIRNODE_AUTHORIZER_REGISTRY_SETTER_ROLE_DESCRIPTION =
        "Airnode authorizer registry setter";
    string
        public constant
        override AIRNODE_FEE_REGISTRY_SETTER_ROLE_DESCRIPTION =
        "Airnode fee registry setter";
    string
        public constant
        override PAYMENT_TOKEN_PRICE_SETTER_ROLE_DESCRIPTION =
        "Payment token price setter";
    string
        public constant
        override AIRNODE_TO_MAXIMUM_WHITELIST_DURATION_SETTER_ROLE_DESCRIPTION =
        "Airnode to maximum whitelist duration setter";
    string
        public constant
        override AIRNODE_TO_PAYMENT_DESTINATION_SETTER_ROLE_DESCRIPTION =
        "Airnode to payment destination setter";

    bytes32 internal adminRoleDescriptionHash;
    bytes32
        internal constant AIRNODE_AUTHORIZER_REGISTRY_SETTER_ROLE_DESCRIPTION_HASH =
        keccak256(
            abi.encodePacked(
                AIRNODE_AUTHORIZER_REGISTRY_SETTER_ROLE_DESCRIPTION
            )
        );
    bytes32
        internal constant AIRNODE_FEE_REGISTRY_SETTER_ROLE_DESCRIPTION_HASH =
        keccak256(
            abi.encodePacked(AIRNODE_FEE_REGISTRY_SETTER_ROLE_DESCRIPTION)
        );
    bytes32 internal constant PAYMENT_TOKEN_PRICE_SETTER_ROLE_DESCRIPTION_HASH =
        keccak256(
            abi.encodePacked(PAYMENT_TOKEN_PRICE_SETTER_ROLE_DESCRIPTION)
        );
    bytes32
        internal constant AIRNODE_TO_MAXIMUM_WHITELIST_DURATION_SETTER_ROLE_DESCRIPTION_HASH =
        keccak256(
            abi.encodePacked(
                AIRNODE_TO_MAXIMUM_WHITELIST_DURATION_SETTER_ROLE_DESCRIPTION
            )
        );
    bytes32
        internal constant AIRNODE_TO_PAYMENT_DESTINATION_SETTER_ROLE_DESCRIPTION_HASH =
        keccak256(
            abi.encodePacked(
                AIRNODE_TO_PAYMENT_DESTINATION_SETTER_ROLE_DESCRIPTION
            )
        );

    /// @notice Address of the manager that manages the related
    /// AccessControlRegistry roles
    address public immutable override manager;

    // Since there will be a single manager, we can derive the roles beforehand
    bytes32 public immutable override adminRole;
    bytes32 public immutable override airnodeAuthorizerRegistrySetterRole;
    bytes32 public immutable override airnodeFeeRegistrySetterRole;
    bytes32 public immutable override paymentTokenPriceSetterRole;
    bytes32
        public immutable
        override airnodeToMaximumWhitelistDurationSetterRole;
    bytes32 public immutable override airnodeToPaymentDestinationSetterRole;

    /// @dev Contracts deployed with the same admin role descriptions will have
    /// the same roles, meaning that granting an account a role will authorize
    /// it in multiple contracts. Unless you want your deployed contract to
    /// reuse the role configuration of another contract, use a unique admin
    /// role description.
    /// @param _accessControlRegistry AccessControlRegistry contract address
    /// @param _adminRoleDescription Admin role description
    /// @param _manager Manager address
    constructor(
        address _accessControlRegistry,
        string memory _adminRoleDescription,
        address _manager
    ) AccessControlClient(_accessControlRegistry) {
        require(
            bytes(_adminRoleDescription).length > 0,
            "Admin role description empty"
        );
        require(_manager != address(0), "Manager address zero");
        adminRoleDescription = _adminRoleDescription;
        adminRoleDescriptionHash = keccak256(
            abi.encodePacked(_adminRoleDescription)
        );
        manager = _manager;
        adminRole = _deriveAdminRole(_manager);
        airnodeAuthorizerRegistrySetterRole = _deriveAirnodeAuthorizerRegistrySetterRole(
            _manager
        );
        airnodeFeeRegistrySetterRole = _deriveAirnodeFeeRegistrySetterRole(
            _manager
        );
        paymentTokenPriceSetterRole = _derivePaymentTokenPriceSetterRole(
            _manager
        );
        airnodeToMaximumWhitelistDurationSetterRole = _deriveAirnodeToMaximumWhitelistDurationSetterRole(
            _manager
        );
        airnodeToPaymentDestinationSetterRole = _deriveAirnodeToPaymentDestinationSetterRole(
            _manager
        );
    }

    /// @notice Derives the admin role for the specific manager address
    /// @param _manager Manager address
    /// @return _adminRole Admin role
    function _deriveAdminRole(address _manager)
        internal
        view
        returns (bytes32 _adminRole)
    {
        _adminRole = _deriveRole(
            _deriveRootRole(_manager),
            adminRoleDescriptionHash
        );
    }

    /// @notice Derives the Airnode authorizer registry setter role for the
    /// specific manager address
    /// @param _manager Manager address
    /// @return _airnodeAuthorizerRegistrySetterRole Airnode authorizer
    /// registry setter role
    function _deriveAirnodeAuthorizerRegistrySetterRole(address _manager)
        internal
        view
        returns (bytes32 _airnodeAuthorizerRegistrySetterRole)
    {
        _airnodeAuthorizerRegistrySetterRole = _deriveRole(
            _deriveAdminRole(_manager),
            AIRNODE_AUTHORIZER_REGISTRY_SETTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @notice Derives the Airnode fee registry setter role for the
    /// specific manager address
    /// @param _manager Manager address
    /// @return _airnodeFeeRegistrySetterRole Airnode fee
    /// registry setter role
    function _deriveAirnodeFeeRegistrySetterRole(address _manager)
        internal
        view
        returns (bytes32 _airnodeFeeRegistrySetterRole)
    {
        _airnodeFeeRegistrySetterRole = _deriveRole(
            _deriveAdminRole(_manager),
            AIRNODE_FEE_REGISTRY_SETTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @notice Derives payment token price setter role for the specific
    /// manager address
    /// @param _manager Manager address
    /// @return _paymentTokenPriceSetterRole Payment token price setter
    /// role
    function _derivePaymentTokenPriceSetterRole(address _manager)
        internal
        view
        returns (bytes32 _paymentTokenPriceSetterRole)
    {
        _paymentTokenPriceSetterRole = _deriveRole(
            _deriveAdminRole(_manager),
            PAYMENT_TOKEN_PRICE_SETTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @notice Derives the Airnode to maximum whitelist duration setter role
    /// for the specific manager address
    /// @param _manager Manager address
    /// @return _airnodeToMaximumWhitelistDurationSetterRole Airnode to maximum
    /// whitelist duration setter role
    function _deriveAirnodeToMaximumWhitelistDurationSetterRole(
        address _manager
    )
        internal
        view
        returns (bytes32 _airnodeToMaximumWhitelistDurationSetterRole)
    {
        _airnodeToMaximumWhitelistDurationSetterRole = _deriveRole(
            _deriveAdminRole(_manager),
            AIRNODE_TO_MAXIMUM_WHITELIST_DURATION_SETTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @notice Derives the Airnode to payment destination setter role for the
    /// specific manager address
    /// @param _manager Manager address
    /// @return _airnodeToPaymentDestinationSetterRole Airnode to payment
    /// destination setter role
    function _deriveAirnodeToPaymentDestinationSetterRole(address _manager)
        internal
        view
        returns (bytes32 _airnodeToPaymentDestinationSetterRole)
    {
        _airnodeToPaymentDestinationSetterRole = _deriveRole(
            _deriveAdminRole(_manager),
            AIRNODE_TO_PAYMENT_DESTINATION_SETTER_ROLE_DESCRIPTION_HASH
        );
    }

    /// @dev Returns if the account has the Airnode authorizer registry setter
    /// role or is the manager
    /// @param account Account address
    /// @return If the account has the Airnode authorizer registry setter role
    /// or is the manager
    function hasAirnodeAuthorizerRegistrySetterRoleOrIsManager(address account)
        internal
        view
        returns (bool)
    {
        return
            manager == account ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                airnodeAuthorizerRegistrySetterRole,
                account
            );
    }

    /// @dev Returns if the account has the Airnode fee registry setter role
    /// or is the manager
    /// @param account Account address
    /// @return If the account has the Airnode fee registry setter role or is the
    /// manager
    function hasAirnodeFeeRegistrySetterRoleOrIsManager(address account)
        internal
        view
        returns (bool)
    {
        return
            manager == account ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                airnodeFeeRegistrySetterRole,
                account
            );
    }

    /// @dev Returns if the account has the payment token price setter role or
    /// is the manager
    /// @param account Account address
    /// @return If the account has the payment token price setter or is the
    /// manager
    function hasPaymentTokenPriceSetterRoleOrIsManager(address account)
        internal
        view
        returns (bool)
    {
        return
            manager == account ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                paymentTokenPriceSetterRole,
                account
            );
    }

    /// @dev Returns if the account has the Airnode to maximum whitelist
    /// duration setter role or is the manager
    /// @param account Account address
    /// @return If the account has the Airnode to maximum whitelist duration
    /// setter or is the manager
    function hasAirnodeToMaximumWhitelistDurationSetterRoleOrIsManager(
        address account
    ) internal view returns (bool) {
        return
            manager == account ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                airnodeToMaximumWhitelistDurationSetterRole,
                account
            );
    }

    /// @dev Returns if the account has the Airnode to payment destination
    /// setter role or is the manager
    /// @param account Account address
    /// @return If the account has the Airnode to payment destination setter or
    /// is the manager
    function hasAirnodeToPaymentDestinationSetterRoleOrIsManager(
        address account
    ) internal view returns (bool) {
        return
            manager == account ||
            IAccessControlRegistry(accessControlRegistry).hasRole(
                airnodeToPaymentDestinationSetterRole,
                account
            );
    }
}
