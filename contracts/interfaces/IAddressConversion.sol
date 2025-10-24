// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAddressConversion {
    /// @dev Returns ss58 pubkey for an address.
    /// @param addr The address.
    /// @return The ss58 pubkey.
    function addressToSS58Pub(address addr) external view returns (bytes32);
}
