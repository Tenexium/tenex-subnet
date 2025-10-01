// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title TenexiumTimelock
 * @notice Thin wrapper around OpenZeppelin TimelockController for deployments
 * @dev This contract is independent from existing storage to avoid layout risk
 */
contract TenexiumTimelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
