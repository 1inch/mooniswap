// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
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

    function sync(VirtualBalance.Data storage self, uint256 balance) internal {
        if (block.timestamp < uint256(self.time).add(DECAY_PERIOD)) {
            update(self, balance);
        }
    }

    function current(VirtualBalance.Data memory self, uint256 realBalance) internal view returns(uint256) {
        uint256 timePassed = Math.min(DECAY_PERIOD, block.timestamp.sub(self.time));
        uint256 timeRemain = DECAY_PERIOD.sub(timePassed);
        return uint256(self.balance).mul(timeRemain).add(
            realBalance.mul(timePassed)
        ).div(DECAY_PERIOD);
    }
}


contract Mooniswap is ERC20, Ownable {
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
        address indexed srcToken,
        address indexed dstToken,
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

    function getBalanceOnAddition(IERC20 token) external view returns(uint256) {
        return virtualBalancesForAddition[token].current(token.balanceOf(address(this)));
    }

    function getBalanceOnRemoval(IERC20 token) external view returns(uint256) {
        return virtualBalancesForRemoval[token].current(token.balanceOf(address(this)));
    }

    function getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount) external view returns(uint256) {
        uint256 srcBalance = virtualBalancesForAddition[srcToken].current(srcToken.balanceOf(address(this)));
        uint256 dstBalance = virtualBalancesForRemoval[dstToken].current(dstToken.balanceOf(address(this)));
        return _getReturn(srcToken, dstToken, amount, srcBalance, dstBalance);
    }

    function swap(IERC20 srcToken, IERC20 dstToken, uint256 amount, uint256 minReturn) external returns(uint256 result) {
        uint256 srcBalance = srcToken.balanceOf(address(this));
        uint256 dstBalance = dstToken.balanceOf(address(this));

        // Save virtual balances to the opposit direction
        uint256 srcRemovalBalance = virtualBalancesForRemoval[srcToken].current(srcBalance);
        uint256 dstAdditionBalance = virtualBalancesForAddition[dstToken].current(dstBalance);
        // Save virtual balances to the same direction
        uint256 srcAdditonBalance = virtualBalancesForAddition[srcToken].current(srcBalance);
        uint256 dstRemovalBalance = virtualBalancesForRemoval[dstToken].current(dstBalance);

        srcToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 confirmed = srcToken.balanceOf(address(this)).sub(srcBalance);

        result = _getReturn(srcToken, dstToken, confirmed, srcAdditonBalance, dstRemovalBalance);
        require(result >= minReturn, "Mooniswap: return is not enough");
        dstToken.safeTransfer(msg.sender, result);

        // Update virtual balances to the opposit direction
        virtualBalancesForRemoval[srcToken].update(srcRemovalBalance);
        virtualBalancesForAddition[dstToken].update(dstAdditionBalance);
        // Update virtual balances to the same direction
        virtualBalancesForAddition[srcToken].sync(srcAdditonBalance.add(confirmed));
        virtualBalancesForRemoval[dstToken].sync(dstRemovalBalance.sub(result));

        emit Swapped(msg.sender, address(srcToken), address(dstToken), confirmed, result);
    }

    function deposit(uint256[] memory amounts, uint256 minReturn) external returns(uint256 fairShare) {
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

    function withdraw(uint256 amount) external {
        uint256 totalSupply = totalSupply();
        _burn(msg.sender, amount);

        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];

            uint256 preBalance = token.balanceOf(address(this));

            uint256 tokenAdditonBalance = virtualBalancesForAddition[token].current(preBalance);
            uint256 tokenRemovalBalance = virtualBalancesForRemoval[token].current(preBalance);

            uint256 value = preBalance.mul(amount).div(totalSupply);
            token.safeTransfer(msg.sender, value);

            virtualBalancesForAddition[token].update(tokenAdditonBalance.sub(value));
            virtualBalancesForRemoval[token].update(tokenRemovalBalance.sub(value));
        }

        emit Withdrawn(msg.sender, amount);
    }

    function _getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount, uint256 srcBalance, uint256 dstBalance) internal view returns(uint256) {
        require(isToken[srcToken] && isToken[dstToken], "Mooniswap: token is not allowed");
        return amount.mul(dstBalance).div(srcBalance.add(amount));
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        require(!isToken[token], "Mooniswap: access denied");
        token.safeTransfer(msg.sender, amount);
    }
}
