// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/UniERC20.sol";
import "./libraries/Sqrt.sol";


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
    using Sqrt for uint256;
    using SafeMath for uint256;
    using UniERC20 for IERC20;
    using VirtualBalance for VirtualBalance.Data;

    struct Balances {
        uint256 src;
        uint256 dst;
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
        address indexed src,
        address indexed dst,
        uint256 amount,
        uint256 srcPreBalance,
        uint256 dstPreBalance,
        uint256 result,
        address referral
    );

    uint256 public constant REFERRAL_SHARE = 20; // 1/share = 5% of LPs revenue
    uint256 public constant BASE_SUPPLY = 1000;  // Total supply on first deposit

    IERC20[] public tokens;
    mapping(IERC20 => bool) public isToken;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForAddition;
    mapping(IERC20 => VirtualBalance.Data) public virtualBalancesForRemoval;

    constructor(string memory name, string memory symbol) public ERC20(name, symbol) {
        require(bytes(name).length > 0, "Mooniswap: name is empty");
        require(bytes(symbol).length > 0, "Mooniswap: symbol is empty");
    }

    function setup(IERC20[] memory assets) external {
        require(tokens.length == 0, "Mooniswap: already initialized");
        require(assets.length == 2, "Mooniswap: only 2 tokens allowed");

        tokens = assets;
        for (uint i = 0; i < assets.length; i++) {
            require(!isToken[assets[i]], "Mooniswap: duplicate tokens");
            isToken[assets[i]] = true;
        }
    }

    function decayPeriod() external pure returns(uint256) {
        return VirtualBalance.DECAY_PERIOD;
    }

    function getBalanceForAddition(IERC20 token) public view returns(uint256) {
        return virtualBalancesForAddition[token].current(token.uniBalanceOf(address(this)));
    }

    function getBalanceForRemoval(IERC20 token) public view returns(uint256) {
        return virtualBalancesForRemoval[token].current(token.uniBalanceOf(address(this)));
    }

    function getReturn(IERC20 src, IERC20 dst, uint256 amount) external view returns(uint256) {
        return _getReturn(src, dst, amount, getBalanceForAddition(src), getBalanceForRemoval(dst));
    }

    function deposit(uint256[] memory amounts, uint256 minReturn) external payable nonReentrant returns(uint256 fairSupply) {
        require(amounts.length == tokens.length, "Mooniswap: wrong amounts length");
        require((msg.value > 0) == (tokens[0].isETH() || tokens[1].isETH()), "Mooniswap: wrong value usage");

        uint256[] memory preBalances = new uint256[](amounts.length);
        for (uint i = 0; i < preBalances.length; i++) {
            IERC20 token = tokens[i];
            preBalances[i] = token.uniBalanceOf(address(this)).sub(token.isETH() ? amounts[i] : 0);
        }

        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            fairSupply = BASE_SUPPLY.mul(99);
            _mint(address(this), BASE_SUPPLY); // Donate up to 1%

            // Use the greatest token amount but not less than 99k for the initial supply
            for (uint i = 0; i < amounts.length; i++) {
                fairSupply = Math.max(fairSupply, amounts[i]);
            }
        }
        else {
            // Pre-compute fair supply
            fairSupply = type(uint256).max;
            for (uint i = 0; i < amounts.length; i++) {
                fairSupply = Math.min(fairSupply, totalSupply.mul(amounts[i]).div(preBalances[i]));
            }
        }

        for (uint i = 0; i < amounts.length; i++) {
            IERC20 token = tokens[i];
            require(amounts[i] > 0, "Mooniswap: amount is zero");

            // Remember both virtual balances
            uint256 removalBalance = virtualBalancesForRemoval[token].current(preBalances[i]);
            uint256 additionBalance = virtualBalancesForAddition[token].current(preBalances[i]);

            token.uniTransferFromSenderToThis(totalSupply == 0 ? amounts[i] : preBalances[i].mul(fairSupply).div(totalSupply));
            if (totalSupply > 0) {
                uint256 confirmed = token.uniBalanceOf(address(this)).sub(preBalances[i]);
                fairSupply = Math.min(fairSupply, totalSupply.mul(confirmed).div(preBalances[i]));
            }

            // Update both virtual balances
            virtualBalancesForRemoval[token].update(removalBalance);
            virtualBalancesForAddition[token].update(additionBalance);
        }

        require(fairSupply > 0 && fairSupply >= minReturn, "Mooniswap: result is not enough");
        _mint(msg.sender, fairSupply);

        emit Deposited(msg.sender, fairSupply);
    }

    function withdraw(uint256 amount, uint256[] memory minReturns) external nonReentrant {
        uint256 totalSupply = totalSupply();
        _burn(msg.sender, amount);

        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];

            uint256 preBalance = token.uniBalanceOf(address(this));

            // Remember both virtual balances
            uint256 tokenAdditonBalance = virtualBalancesForAddition[token].current(preBalance);
            uint256 tokenRemovalBalance = virtualBalancesForRemoval[token].current(preBalance);

            uint256 value = preBalance.mul(amount).div(totalSupply);
            token.uniTransfer(msg.sender, value);
            require(i >= minReturns.length || value >= minReturns[i], "Mooniswap: result is not enough");

            // Update both virtual balances
            virtualBalancesForAddition[token].update(
                tokenAdditonBalance.sub(value)
            );
            virtualBalancesForRemoval[token].update(
                tokenRemovalBalance.sub(Math.min(tokenRemovalBalance, value))
            );
        }

        emit Withdrawn(msg.sender, amount);
    }

    function swap(IERC20 src, IERC20 dst, uint256 amount, uint256 minReturn, address referral) external payable nonReentrant returns(uint256 result) {
        require((msg.value == amount) == src.isETH(), "Mooniswap: wrong value usage");

        Balances memory balances = Balances({
            src: src.uniBalanceOf(address(this)).sub(src.isETH() ? msg.value : 0),
            dst: dst.uniBalanceOf(address(this))
        });

        // Remember virtual balances to the opposit direction
        uint256 srcRemovalBalance = virtualBalancesForRemoval[src].current(balances.src);
        uint256 dstAdditionBalance = virtualBalancesForAddition[dst].current(balances.dst);
        // Remember virtual balances to the same direction
        uint256 srcAdditonBalance = virtualBalancesForAddition[src].current(balances.src);
        uint256 dstRemovalBalance = virtualBalancesForRemoval[dst].current(balances.dst);

        src.uniTransferFromSenderToThis(amount);
        uint256 confirmed = src.uniBalanceOf(address(this)).sub(balances.src);

        result = _getReturn(src, dst, confirmed, srcAdditonBalance, dstRemovalBalance);
        require(result > 0 && result >= minReturn, "Mooniswap: return is not enough");
        dst.uniTransfer(msg.sender, result);

        // Update virtual balances to the opposit direction
        virtualBalancesForRemoval[src].update(srcRemovalBalance);
        virtualBalancesForAddition[dst].update(dstAdditionBalance);
        // Update virtual balances to the same direction only at imbalanced state
        if (srcAdditonBalance != balances.src) {
            virtualBalancesForAddition[src].update(srcAdditonBalance.add(confirmed));
        }
        if (dstRemovalBalance != balances.dst) {
            virtualBalancesForRemoval[dst].update(dstRemovalBalance.sub(result));
        }

        emit Swapped(msg.sender, address(src), address(dst), confirmed, balances.src, balances.dst, result, referral);

        if (referral != address(0)) {
            uint256 invariantRatio = uint256(1e36);
            invariantRatio = invariantRatio.mul(balances.src.add(amount)).div(balances.src);
            invariantRatio = invariantRatio.mul(balances.dst.sub(result)).div(balances.dst);
            _mint(referral, invariantRatio.sqrt().sub(1e18).mul(totalSupply()).div(1e18).div(REFERRAL_SHARE));
        }
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        uint256[] memory balances = new uint256[](tokens.length);
        for (uint i = 0; i < balances.length; i++) {
            balances[i] = tokens[i].uniBalanceOf(address(this));
        }

        token.uniTransfer(msg.sender, amount);

        for (uint i = 0; i < balances.length; i++) {
            require(tokens[i].uniBalanceOf(address(this)) >= balances[i], "Mooniswap: access denied");
        }
        require(balanceOf(address(this)) >= BASE_SUPPLY, "Mooniswap: access denied");
    }

    function _getReturn(IERC20 src, IERC20 dst, uint256 amount, uint256 srcBalance, uint256 dstBalance) internal view returns(uint256) {
        if (isToken[src] && isToken[dst] && src != dst && amount > 0) {
            return amount.mul(dstBalance).div(srcBalance.add(amount));
        }
    }
}
