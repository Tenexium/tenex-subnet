// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/INeuron.sol";
import "./interfaces/IAddressConversion.sol";

/**
 * @notice Interface for TenexiumProtocol setAssociate function
 */
interface ITenexiumProtocol {
    function setAssociate(bytes32 hotkey, address user) external returns (bool);
}

/**
 * @title TenexiumRegister
 * @notice Upgradeable contract for registering users to Bittensor subnets and associating with TenexiumProtocol
 * @dev Uses delegatecall to preserve msg.sender context in neuron precompile calls
 */
contract TenexiumRegister is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    // ==================== ERRORS ====================

    error InvalidValue();
    error BurnedRegisterFailed();
    error SetAssociateFailed();
    error FunctionNotFound();

    // ==================== CONSTANTS ====================

    // Bittensor Neuron precompile
    INeuron public constant NEURON_PRECOMPILE = INeuron(0x0000000000000000000000000000000000000804);

    // Tenex subnet ID
    uint16 public constant TENEX_NETUID = 67;

    // ==================== EVENTS ====================

    event Registered(address indexed user, uint16 indexed netuid, bytes32 indexed hotkey);

    event TenexiumProtocolUpdated(address indexed oldProtocol, address indexed newProtocol);

    event AddressConversionUpdated(address indexed oldContract, address indexed newContract);

    // ==================== STATE VARIABLES ====================

    // Address conversion contract
    IAddressConversion public addressConversionContract;

    // TenexiumProtocol contract
    address public tenexiumProtocol;

    // ==================== CONSTRUCTOR ====================

    /**
     * @notice Constructor for UUPS proxy pattern
     */
    constructor() {
        _disableInitializers();
    }

    // ==================== INITIALIZATION ====================

    /**
     * @notice Initialize the contract
     * @param _addressConversionContract Address of the address conversion contract
     * @param _tenexiumProtocol Address of the TenexiumProtocol contract
     */
    function initialize(address _addressConversionContract, address _tenexiumProtocol) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (_addressConversionContract == address(0)) revert InvalidValue();
        if (_tenexiumProtocol == address(0)) revert InvalidValue();

        addressConversionContract = IAddressConversion(_addressConversionContract);
        tenexiumProtocol = _tenexiumProtocol;
    }

    // ==================== REGISTRATION FUNCTIONS ====================

    /**
     * @notice Register user to Tenex subnet (67) and associate with TenexiumProtocol
     * @dev First calls burnedRegister on neuron precompile, then setAssociate on TenexiumProtocol
     * @dev Hotkey is automatically derived from msg.sender using addressConversionContract
     * @dev Netuid is hardcoded to TENEX_NETUID (67)
     */
    function register() external payable nonReentrant {
        // Get hotkey from msg.sender's address
        bytes32 hotkey = addressConversionContract.addressToSS58Pub(msg.sender);
        if (hotkey == bytes32(0)) revert InvalidValue();

        // Step 1: Call burnedRegister using delegatecall to preserve msg.sender
        bytes memory burnedRegisterData =
            abi.encodeWithSelector(NEURON_PRECOMPILE.burnedRegister.selector, TENEX_NETUID, hotkey);

        (bool burnSuccess,) = address(NEURON_PRECOMPILE).delegatecall{gas: gasleft()}(burnedRegisterData);
        if (!burnSuccess) revert BurnedRegisterFailed();

        // Step 2: Call setAssociate on TenexiumProtocol
        ITenexiumProtocol protocol = ITenexiumProtocol(tenexiumProtocol);
        bool associateSuccess = protocol.setAssociate(hotkey, msg.sender);
        if (!associateSuccess) revert SetAssociateFailed();

        emit Registered(msg.sender, TENEX_NETUID, hotkey);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @notice Update TenexiumProtocol contract address (owner only)
     * @param _tenexiumProtocol New TenexiumProtocol contract address
     */
    function updateTenexiumProtocol(address _tenexiumProtocol) external onlyOwner {
        if (_tenexiumProtocol == address(0)) revert InvalidValue();
        address oldProtocol = tenexiumProtocol;
        tenexiumProtocol = _tenexiumProtocol;
        emit TenexiumProtocolUpdated(oldProtocol, _tenexiumProtocol);
    }

    /**
     * @notice Update address conversion contract (owner only)
     * @param _addressConversionContract New address conversion contract
     */
    function updateAddressConversionContract(address _addressConversionContract) external onlyOwner {
        if (_addressConversionContract == address(0)) revert InvalidValue();
        address oldContract = address(addressConversionContract);
        addressConversionContract = IAddressConversion(_addressConversionContract);
        emit AddressConversionUpdated(oldContract, _addressConversionContract);
    }

    /**
     * @notice Emergency withdraw function (owner only)
     * @dev Allows owner to withdraw any TAO stuck in the contract
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InvalidValue();

        (bool success,) = payable(owner()).call{value: balance}("");
        if (!success) revert InvalidValue();
    }

    // ==================== VIEW FUNCTIONS ====================

    /**
     * @notice Get SS58 public key for an address
     * @param addr Address to convert
     * @return SS58 public key as bytes32
     */
    function getSS58PubKey(address addr) external view returns (bytes32) {
        return addressConversionContract.addressToSS58Pub(addr);
    }

    // ==================== UPGRADES (UUPS) ====================

    /**
     * @notice Authorize upgrade (owner only)
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ==================== FALLBACK ====================

    /**
     * @notice Allow contract to receive TAO
     */
    receive() external payable {}

    /**
     * @notice Prohibit fallback calls
     */
    fallback() external payable {
        revert FunctionNotFound();
    }
}

