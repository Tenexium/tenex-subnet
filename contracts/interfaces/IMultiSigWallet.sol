// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMultiSigWallet {
    /// @dev Returns the owners of the multisig wallet.
    /// @return The owners of the multisig wallet.
    function getOwners() external view returns (address[] memory);
}
