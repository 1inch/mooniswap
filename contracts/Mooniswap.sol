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

    function update(VirtualBalance.Data storage self, uint256 balance) internal {
        self.balance = uint216(balance);
        self.time = uint40(block.timestamp);
    }

    function current(VirtualBalance.Data memory self, uint256 realBalance, uint256 decayPeriod) internal view returns(uint256) {
        uint256 timePassed = Math.min(decayPeriod, block.timestamp.sub(self.time));
        uint256 timeRemain = decayPeriod.sub(timePassed);
        return uint256(self.balance).mul(timeRemain).add(
            realBalance.mul(timePassed)
        ).div(decayPeriod);
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

    uint256 public constant DECAY_PERIOD = 5 minutes;

    IERC20[] public tokens;
    mapping(IERC20 => bool) public isToken;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForAddition;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForRemoval;

    constructor(
        IERC20[] memory _tokens,
        string memory name,
        string memory symbol
    )
        public
        ERC20(name, symbol)
    {
        require(_tokens.length == 2, "Mooniswap: only 2 tokens allowed");
        require(bytes(name).length > 0, "Mooniswap: name is empty");
        require(bytes(symbol).length > 0, "Mooniswap: symbol is empty");

        tokens = _tokens;
        for (uint i = 0; i < _tokens.length; i++) {
            require(!isToken[_tokens[i]], "Mooniswap: duplicate tokens");
            isToken[_tokens[i]] = true;
        }
    }

    function getBalanceOnAddition(IERC20 token) public view returns(uint256) {
        return virtualBalancesForAddition[token].current(token.balanceOf(address(this)), DECAY_PERIOD);
    }

    function getBalanceOnRemoval(IERC20 token) public view returns(uint256) {
        return virtualBalancesForRemoval[token].current(token.balanceOf(address(this)), DECAY_PERIOD);
    }

    function getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount) public view returns(uint256) {
        return _getReturn(srcToken, dstToken, amount, 0);
    }

    function swap(
        IERC20 srcToken,
        IERC20 dstToken,
        uint256 amount,
        uint256 minReturn
    )
        public
        returns(uint256 result)
    {
        uint256 srcBalance = srcToken.balanceOf(address(this));
        uint256 dstBalance = dstToken.balanceOf(address(this));

        // Save virtual balances to the opposit direction
        uint256 srcRemovalBalance = virtualBalancesForRemoval[srcToken].current(srcBalance, DECAY_PERIOD);
        uint256 dstAdditionBalance = virtualBalancesForAddition[dstToken].current(dstBalance, DECAY_PERIOD);
        // Save virtual balances to the same direction
        uint256 srcAdditonBalance = virtualBalancesForAddition[srcToken].current(srcBalance, DECAY_PERIOD);
        uint256 dstRemovalBalance = virtualBalancesForRemoval[dstToken].current(dstBalance, DECAY_PERIOD);

        srcToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 confirmed = srcToken.balanceOf(address(this)).sub(srcBalance);

        result = _getReturn(srcToken, dstToken, confirmed, confirmed);
        require(result >= minReturn, "Mooniswap: return is not enough");
        dstToken.safeTransfer(msg.sender, result);

        // Update virtual balances to the opposit direction
        virtualBalancesForRemoval[srcToken].update(srcRemovalBalance);
        virtualBalancesForAddition[dstToken].update(dstAdditionBalance);
        // Update virtual balances to the same direction
        virtualBalancesForAddition[srcToken].update(srcAdditonBalance.add(confirmed));
        virtualBalancesForRemoval[dstToken].update(dstRemovalBalance.sub(result));

        emit Swapped(
            msg.sender,
            address(srcToken),
            address(dstToken),
            confirmed,
            result
        );
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
            uint256 removalBalance = virtualBalancesForRemoval[token].current(preBalance, DECAY_PERIOD);
            uint256 additionBalance = virtualBalancesForAddition[token].current(preBalance, DECAY_PERIOD);

            preBalance = token.balanceOf(address(this));
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

            uint256 tokenAdditonBalance = virtualBalancesForAddition[token].current(preBalance, DECAY_PERIOD);
            uint256 tokenRemovalBalance = virtualBalancesForRemoval[token].current(preBalance, DECAY_PERIOD);

            uint256 value = preBalance.mul(amount).div(totalSupply);
            token.safeTransfer(msg.sender, value);

            virtualBalancesForAddition[token].update(tokenAdditonBalance.sub(value));
            virtualBalancesForRemoval[token].update(tokenRemovalBalance.sub(value));
        }

        emit Withdrawn(msg.sender, amount);
    }

    // Internal

    function _getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount, uint256 subSrcDeposited) internal view returns(uint256) {
        if (!isToken[srcToken] || !isToken[dstToken]) {
            return 0;
        }

        uint256 dstBalance = getBalanceOnRemoval(dstToken);
        uint256 srcBalance = virtualBalancesForAddition[srcToken].current(
            srcToken.balanceOf(address(this)).sub(subSrcDeposited),
            DECAY_PERIOD
        );
        return amount.mul(dstBalance).div(srcBalance.add(amount));
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        require(!isToken[token], "Mooniswap: access denied");
        token.safeTransfer(msg.sender, amount);
    }
}
