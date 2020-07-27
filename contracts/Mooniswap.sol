// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


library VirtualBalance {
    using SafeMath for uint256;

    struct Data {
        uint216 balance;
        uint40 time;
    }

    uint256 public constant DECAY_PERIOD = 5 minutes;

    function update(VirtualBalance.Data storage self, uint256 balance) internal {
        self.balance = uint216(balance);
        self.time = uint40(block.timestamp);
    }

    function current(VirtualBalance.Data memory self, uint256 realBalance) internal view returns(uint256) {
        uint256 timePassed = Math.min(DECAY_PERIOD, block.timestamp.sub(self.time));
        uint256 timeRemain = DECAY_PERIOD.sub(timePassed);
        return uint256(self.balance).mul(timeRemain).add(
            realBalance.mul(timePassed)
        ).div(DECAY_PERIOD);
    }
}


contract Mooniswap is ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using VirtualBalance for VirtualBalance.Data;

    event Deposited(
        address indexed account,
        uint256 amount
    );

    event Withdrawn(
        address indexed account,
        uint256 amount
    );

    event Swapped(
        address indexed account,
        address indexed src,
        address indexed dst,
        uint256 amount,
        uint256 result
    );

    IERC20[] public tokens;
    mapping(IERC20 => bool) public isToken;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForAddition;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForRemoval;

    constructor(IERC20[] memory assets, string memory name, string memory symbol) public ERC20(name, symbol) {
        require(assets.length == 2, "Mooniswap: only 2 tokens allowed");
        require(bytes(name).length > 0, "Mooniswap: name is empty");
        require(bytes(symbol).length > 0, "Mooniswap: symbol is empty");

        tokens = assets;
        for (uint i = 0; i < assets.length; i++) {
            require(!isToken[assets[i]], "Mooniswap: duplicate tokens");
            isToken[assets[i]] = true;
        }
    }

    function decayPeriod() external pure returns(uint256) {
        return VirtualBalance.DECAY_PERIOD;
    }

    function getBalanceOnAddition(IERC20 token) public view returns(uint256) {
        return virtualBalancesForAddition[token].current(token.balanceOf(address(this)));
    }

    function getBalanceOnRemoval(IERC20 token) public view returns(uint256) {
        return virtualBalancesForRemoval[token].current(token.balanceOf(address(this)));
    }

    function getReturn(IERC20 src, IERC20 dst, uint256 amount) external view returns(uint256) {
        return _getReturn(src, dst, amount, getBalanceOnAddition(src), getBalanceOnRemoval(dst));
    }

    function swap(IERC20 src, IERC20 dst, uint256 amount, uint256 minReturn) external nonReentrant returns(uint256 result) {
        uint256 srcBalance = src.balanceOf(address(this));
        uint256 dstBalance = dst.balanceOf(address(this));

        // Save virtual balances to the opposit direction
        uint256 srcRemovalBalance = virtualBalancesForRemoval[src].current(srcBalance);
        uint256 dstAdditionBalance = virtualBalancesForAddition[dst].current(dstBalance);
        // Save virtual balances to the same direction
        uint256 srcAdditonBalance = virtualBalancesForAddition[src].current(srcBalance);
        uint256 dstRemovalBalance = virtualBalancesForRemoval[dst].current(dstBalance);

        src.safeTransferFrom(msg.sender, address(this), amount);
        uint256 confirmed = src.balanceOf(address(this)).sub(srcBalance);

        result = _getReturn(src, dst, confirmed, srcAdditonBalance, dstRemovalBalance);
        require(result > 0 && result >= minReturn, "Mooniswap: return is not enough");
        dst.safeTransfer(msg.sender, result);

        // Update virtual balances to the opposit direction
        virtualBalancesForRemoval[src].update(srcRemovalBalance);
        virtualBalancesForAddition[dst].update(dstAdditionBalance);
        // Update virtual balances to the same direction
        if (srcAdditonBalance != srcBalance) {
            virtualBalancesForAddition[src].update(srcAdditonBalance.add(confirmed));
        }
        if (dstRemovalBalance != dstBalance) {
            virtualBalancesForRemoval[dst].update(dstRemovalBalance.sub(result));
        }

        emit Swapped(msg.sender, address(src), address(dst), confirmed, result);
    }

    function deposit(uint256[] memory amounts, uint256 minReturn) external nonReentrant returns(uint256 fairShare) {
        require(amounts.length == tokens.length, "Mooniswap: wrong amounts length");

        uint256 totalSupply = totalSupply();
        bool initialDepsoit = (totalSupply == 0);
        if (initialDepsoit) {
            // Use the greatest token amount for the first deposit
            for (uint i = 0; i < amounts.length; i++) {
                if (amounts[i] > totalSupply) {
                    totalSupply = amounts[i];
                }
            }
        }

        fairShare = type(uint256).max;
        for (uint i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Mooniswap: amount is zero");

            IERC20 token = tokens[i];
            uint256 preBalance = token.balanceOf(address(this));

            // Save both virtual balances
            uint256 removalBalance = virtualBalancesForRemoval[token].current(preBalance);
            uint256 additionBalance = virtualBalancesForAddition[token].current(preBalance);

            token.safeTransferFrom(msg.sender, address(this), amounts[i]);
            uint256 confirmed = token.balanceOf(address(this)).sub(preBalance);

            // Update both virtual balances
            virtualBalancesForRemoval[token].update(removalBalance);
            virtualBalancesForAddition[token].update(additionBalance);

            uint256 share = initialDepsoit ? totalSupply : totalSupply.mul(confirmed).div(preBalance);
            if (share < fairShare) {
                fairShare = share;
            }
        }

        require(fairShare >= minReturn, "Mooniswap: result is not enough");
        _mint(msg.sender, fairShare);

        emit Deposited(msg.sender, fairShare);
    }

    function withdraw(uint256 amount, uint256[] memory minReturns) external nonReentrant {
        uint256 totalSupply = totalSupply();
        _burn(msg.sender, amount);

        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];

            uint256 preBalance = token.balanceOf(address(this));

            uint256 tokenAdditonBalance = virtualBalancesForAddition[token].current(preBalance);
            uint256 tokenRemovalBalance = virtualBalancesForRemoval[token].current(preBalance);

            uint256 value = preBalance.mul(amount).div(totalSupply);
            token.safeTransfer(msg.sender, value);
            require(i >= minReturns.length || value >= minReturns[i], "Mooniswap: result is not enough");

            virtualBalancesForAddition[token].update(
                tokenAdditonBalance.sub(Math.min(tokenAdditonBalance, value))
            );
            virtualBalancesForRemoval[token].update(
                tokenRemovalBalance.sub(Math.min(tokenRemovalBalance, value))
            );
        }

        emit Withdrawn(msg.sender, amount);
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        require(!isToken[token], "Mooniswap: access denied");
        token.safeTransfer(msg.sender, amount);
    }

    function _getReturn(IERC20 src, IERC20 dst, uint256 amount, uint256 srcBalance, uint256 dstBalance) internal view returns(uint256) {
        require(isToken[src] && isToken[dst], "Mooniswap: token is not allowed");
        return amount.mul(dstBalance).div(srcBalance.add(amount));
    }
}
