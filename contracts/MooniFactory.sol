// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/UniERC20.sol";
import "./Mooniswap.sol";


contract MooniFactory is Ownable {
    using UniERC20 for IERC20;

    event Deployed(
        address indexed mooniswap,
        address indexed token1,
        address indexed token2
    );

    Mooniswap[] public allPools;
    mapping(address => mapping(address => Mooniswap)) public pools;

    function getAllPools() external view returns(Mooniswap[] memory) {
        return allPools;
    }

    function deploy(address tokenA, address tokenB) public returns(Mooniswap pool) {
        require(tokenA != tokenB, "Factory: not support same tokens");

        (address token1, address token2) = _sortTokens(tokenA, tokenB);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token1);
        tokens[1] = IERC20(token2);
        pool = new Mooniswap{salt: salt(token1, token2)}("Mooniswap", "MOON-V1");
        pool.setup(tokens);
        pool.transferOwnership(owner());
        pools[token1][token2] = pool;
        pools[token2][token1] = pool;
        allPools.push(pool);

        emit Deployed(
            address(pool),
            token1,
            token2
        );
    }

    function salt(address tokenA, address tokenB) public pure returns(bytes32) {
        return bytes32(
            uint256(uint128(uint160(tokenB))) |
            (uint256(uint128(uint160(tokenA))) << 128)
        );
    }

    function _sortTokens(address tokenA, address tokenB) internal pure returns(address, address) {
        if (tokenA < tokenB) {
            return (tokenA, tokenB);
        }
        return (tokenB, tokenA);
    }
}
