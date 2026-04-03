// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/**
 * Library used to interact with PoolManager.sol to settle any open deltas:
 * - To settle a positive delta (a credit to the user), a user may take or mint.
 * - To settle a negative delta (a debt on the user), a user make transfer or burn to pay off a debt.
 *
 * @dev Note that sync() is called before any erc-20 transfer in `settle`.
 */
library CurrencySettler {
    /**
     * Settle (pay) a currency to the PoolManager.
     * 结算（支付）一种货币到池管理器。
     * @param currency Currency to settle 要结算的货币
     * @param manager IPoolManager to settle to 要结算到的池管理器
     * @param payer Address of the payer, the token sender 支付者的地址，代币发送者
     * @param amount Amount to send 要发送的数量
     * @param burn If true, burn the ERC-6909 token, otherwise ERC20-transfer to the PoolManager 如果为true，燃烧ERC-6909代币，否则ERC20-transfer到池管理器
     */
    function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal {
        // For native currencies or burns, calling sync is not required 对于原生货币或燃烧，调用sync是不必要的
        // short circuit for ERC-6909 burns to support ERC-6909-wrapped native tokens 短路用于ERC-6909燃烧以支持ERC-6909包装的原生代币
        if (burn) {
            // 燃烧ERC-6909代币
            manager.burn(payer, currency.toId(), amount);
        } else if (currency.isAddressZero()) {
            // 原生货币结算
            manager.settle{value: amount}();
        } else {
            // 同步货币
            manager.sync(currency);
            // 如果支付者不是当前合约，则从支付者转移代币到池管理器
            if (payer != address(this)) {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount);
            }
            manager.settle();
        }
    }

    /**
     * Take (receive) a currency from the PoolManager.
     *
     * @param currency Currency to take
     * @param manager IPoolManager to take from
     * @param recipient Address of the recipient, the token receiver
     * @param amount Amount to receive
     * @param claims If true, mint the ERC-6909 token, otherwise ERC20-transfer from the PoolManager to recipient
     */
    function take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal {
        claims ? manager.mint(recipient, currency.toId(), amount) : manager.take(currency, recipient, amount);
    }
}
