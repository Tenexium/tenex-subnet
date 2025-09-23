// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/TenexiumStorage.sol";
import "../libraries/TenexiumErrors.sol";
import "../libraries/AlphaMath.sol";

/**
 * @title PrecompileAdapter
 * @notice Adapter for interacting with Bittensor precompiles (staking, alpha, metagraph)
 */
abstract contract PrecompileAdapter is TenexiumStorage {
    using AlphaMath for uint256;

    /**
     * @notice Stake TAO for Alpha tokens using the staking precompile
     * @param validatorHotkey Validator hotkey
     * @param taoAmount TAO amount to stake (wei)
     * @param alphaNetuid Alpha subnet ID
     * @return alphaReceived Alpha tokens received (in alpha base units)
     */
    function _stakeTaoForAlpha(bytes32 validatorHotkey, uint256 taoAmount, uint16 alphaNetuid)
        internal
        returns (uint256 alphaReceived)
    {
        if (protocolSs58Address == bytes32(0)) revert TenexiumErrors.InvalidValue();
        uint256 initialStake = STAKING_PRECOMPILE.getStake(validatorHotkey, protocolSs58Address, uint256(alphaNetuid));

        uint256 amountRao = taoAmount.weiToRao();
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.addStake.selector, validatorHotkey, amountRao, uint256(alphaNetuid)
        );
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.StakeFailed();

        uint256 finalStake = STAKING_PRECOMPILE.getStake(validatorHotkey, protocolSs58Address, uint256(alphaNetuid));

        alphaReceived = finalStake - initialStake;
        return alphaReceived;
    }

    /**
     * @notice Unstake Alpha tokens for TAO using the staking precompile
     * @param validatorHotkey Validator hotkey
     * @param alphaAmount Alpha amount to unstake (alpha base units)
     * @param alphaNetuid Alpha subnet ID
     * @return taoReceived TAO received from unstaking (wei)
     */
    function _unstakeAlphaForTao(bytes32 validatorHotkey, uint256 alphaAmount, uint16 alphaNetuid)
        internal
        returns (uint256 taoReceived)
    {
        uint256 initialBalance = address(this).balance;

        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.removeStake.selector, validatorHotkey, alphaAmount, uint256(alphaNetuid)
        );
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.UnstakeFailed();

        uint256 finalBalance = address(this).balance;
        taoReceived = finalBalance - initialBalance;
        return taoReceived;
    }

    /**
     * @notice Transfer staked alpha to another coldkey via staking precompile
     * @param destinationColdkey Destination coldkey
     * @param hotkey Validator hotkey
     * @param originNetuid Origin subnet id
     * @param destinationNetuid Destination subnet id
     * @param amount Alpha amount to transfer (alpha base units)
     */
    function _transferStake(
        bytes32 destinationColdkey,
        bytes32 hotkey,
        uint256 originNetuid,
        uint256 destinationNetuid,
        uint256 amount
    ) internal {
        bytes memory data = abi.encodeWithSelector(
            STAKING_PRECOMPILE.transferStake.selector,
            destinationColdkey,
            hotkey,
            originNetuid,
            destinationNetuid,
            amount
        );
        (bool success,) = address(STAKING_PRECOMPILE).call{gas: gasleft()}(data);
        if (!success) revert TenexiumErrors.TransferFailed();
    }

    /**
     * @notice Select a validator hotkey (prefers protocol-level hotkey, fallback highest vTrust)
     */
    function _getAlphaValidatorHotkey(uint16 alphaNetuid) internal view returns (bytes32 validatorHotkey) {
        if (protocolValidatorHotkey != bytes32(0)) {
            return protocolValidatorHotkey;
        }

        uint16 uidCount = METAGRAPH_PRECOMPILE.getUidCount(alphaNetuid);
        uint16 bestUid = 0;
        uint16 bestV = 0;
        for (uint16 i = 0; i < uidCount; i++) {
            uint16 v = METAGRAPH_PRECOMPILE.getVtrust(alphaNetuid, i);
            if (v > bestV) {
                bestV = v;
                bestUid = i;
            }
        }
        bytes32 hotkey = METAGRAPH_PRECOMPILE.getHotkey(alphaNetuid, bestUid);
        return hotkey == bytes32(0) ? protocolValidatorHotkey : hotkey;
    }
}
