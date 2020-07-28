// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


library UniERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    function isETH(IERC20 token) internal pure returns(bool) {
        return (address(token) == address(0));
    }

    function uniTransfer(IERC20 token, address payable to, uint256 amount) internal {
        if (amount > 0) {
            if (isETH(token)) {
                to.transfer(amount);
            } else {
                token.safeTransfer(to, amount);
            }
        }
    }

    function uniTransferFromSenderToThis(IERC20 token, uint256 amount) internal {
        if (amount > 0) {
            if (isETH(token)) {
                require(msg.value >= amount, "UniERC20: not enough value");
                if (msg.value > amount) {
                    // Return remainder if exist
                    msg.sender.transfer(msg.value.sub(amount));
                }
            } else {
                token.safeTransferFrom(msg.sender, address(this), amount);
            }
        }
    }

    function uniBalanceOf(IERC20 token, address account) internal view returns (uint256) {
        if (isETH(token)) {
            return account.balance;
        } else {
            return token.balanceOf(account);
        }
    }
}
