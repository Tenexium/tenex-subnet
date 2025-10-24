// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IInsuranceManager {
    function fund(uint256 amount) external;
    function getNetBalance() external view returns (uint256);
}
