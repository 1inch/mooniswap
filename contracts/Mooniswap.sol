// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


contract Mooniswap is ERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct VirtualBalance {
        uint256 balance;
        uint256 time;
    }

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
    mapping(IERC20 => VirtualBalance) public virtualBalancesForAddition;
    mapping(IERC20 => VirtualBalance) public virtualBalancesForRemoval;

    modifier saveVirtualBalanceForRemoval(IERC20 token) {
        uint256 tokenBalance = getBalanceOnRemoval(token);
        _;
        virtualBalancesForRemoval[token] = VirtualBalance({
            balance: tokenBalance,
            time: block.timestamp
        });
    }

    modifier saveVirtualBalanceForAddition(IERC20 token) {
        uint256 tokenBalance = getBalanceOnAddition(token);
        _;
        virtualBalancesForAddition[token] = VirtualBalance({
            balance: tokenBalance,
            time: block.timestamp
        });
    }

    constructor(
        IERC20[] memory _tokens,
        string memory name,
        string memory symbol
    )
        public
        ERC20(name, symbol)
    {
        require(_tokens.length == 2, "Mooniswap: supports only 2 tokens");
        require(bytes(name).length > 0, "Mooniswap: name should not be empty");
        require(bytes(symbol).length > 0, "Mooniswap: symbol should not be empty");

        tokens = _tokens;
        for (uint i = 0; i < _tokens.length; i++) {
            require(!isToken[_tokens[i]], "Mooniswap: token duplicates are not allowed");
            isToken[_tokens[i]] = true;
        }
    }

    function getBalanceOnAddition(IERC20 token) public view returns(uint256) {
        return _getBalance(virtualBalancesForAddition[token], token.balanceOf(address(this)));
    }

    function getBalanceOnRemoval(IERC20 token) public view returns(uint256) {
        return _getBalance(virtualBalancesForRemoval[token], token.balanceOf(address(this)));
    }

    function getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount) public view returns(uint256) {
        return _getReturn(srcToken, dstToken, amount, 0);
    }

    function swap(IERC20 srcToken, IERC20 dstToken, uint256 amount, uint256 minReturn)
        external
        saveVirtualBalanceForRemoval(srcToken)
        saveVirtualBalanceForAddition(dstToken)
        returns(uint256 result)
    {
        uint256 srcAdditonBalance = getBalanceOnAddition(srcToken);
        uint256 dstRemovalBalance = getBalanceOnRemoval(dstToken);

        uint256 preBalance = srcToken.balanceOf(address(this));
        srcToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 confirmed = srcToken.balanceOf(address(this)).sub(preBalance);

        result = _getReturn(srcToken, dstToken, confirmed, confirmed);
        require(result >= minReturn, "Mooniswap: return amount less than minReturn");
        dstToken.safeTransfer(msg.sender, result);

        // Update virtual balances to the same direction
        virtualBalancesForAddition[srcToken] = VirtualBalance({
            balance: srcAdditonBalance.add(confirmed),
            time: block.timestamp
        });
        virtualBalancesForRemoval[dstToken] = VirtualBalance({
            balance: dstRemovalBalance.sub(result),
            time: block.timestamp
        });
    }

    function deposit(uint256[] memory amounts, uint256 minReturn) external returns(uint256 worstShare) {
        require(amounts.length == tokens.length, "Mooniswap: amounts length invalid");

        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            // Use the greatest token amount for the first deposit
            for (uint i = 0; i < amounts.length; i++) {
                if (amounts[i] > totalSupply) {
                    totalSupply = amounts[i];
                }
            }
        }

        worstShare = type(uint256).max;
        for (uint i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, "Mooniswap: zero ammount not allowed");

            uint256 preBalance = tokens[i].balanceOf(address(this));
            tokens[i].safeTransferFrom(msg.sender, address(this), amounts[i]);
            uint256 confirmed = tokens[i].balanceOf(address(this)).sub(preBalance);

            uint256 share = (preBalance == 0) ? totalSupply : totalSupply.mul(confirmed).div(preBalance);
            if (share < worstShare) {
                worstShare = share;
            }
        }

        require(worstShare >= minReturn, "Mooniswap: result was less than minReturn");
        _mint(msg.sender, worstShare);

        emit Deposited(msg.sender, worstShare);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);

        uint256 totalSupply = totalSupply();
        for (uint i = 0; i < tokens.length; i++) {
            uint256 value = tokens[i].balanceOf(address(this)).mul(amount).div(totalSupply);
            tokens[i].safeTransfer(msg.sender, value);
        }

        emit Withdrawn(msg.sender, amount);
    }

    // Internal

    function _getBalance(VirtualBalance memory virtualBalance, uint256 realBalance)
        internal
        view
        returns(uint256)
    {
        uint256 timePassed = Math.min(DECAY_PERIOD, block.timestamp.sub(virtualBalance.time));
        uint256 timeRemain = DECAY_PERIOD.sub(timePassed);
        return virtualBalance.balance.mul(timeRemain).add(
            realBalance.mul(timePassed)
        ).div(DECAY_PERIOD);
    }

    function _depositToken(IERC20 token, uint256 amount)
        internal
        saveVirtualBalanceForRemoval(token)
        saveVirtualBalanceForAddition(token)
        returns(uint256)
    {
        uint256 tokenBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        return token.balanceOf(address(this)).sub(tokenBalance);
    }

    function _getReturn(IERC20 srcToken, IERC20 dstToken, uint256 amount, uint256 subSrcDeposited) internal view returns(uint256) {
        if (!isToken[srcToken] || !isToken[dstToken]) {
            return 0;
        }

        uint256 dstBalance = getBalanceOnRemoval(dstToken);
        uint256 srcBalance = _getBalance(
            virtualBalancesForAddition[srcToken],
            srcToken.balanceOf(address(this)).sub(subSrcDeposited)
        );
        return amount.mul(dstBalance).div(srcBalance.add(amount));
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        require(!isToken[token], "Mooniswap: access denied");
        token.safeTransfer(msg.sender, amount);
    }
}
