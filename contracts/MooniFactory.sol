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
    mapping(Mooniswap => bool) public isPool;
    mapping(IERC20 => mapping(IERC20 => Mooniswap)) public pools;

    function getAllPools() external view returns(Mooniswap[] memory) {
        return allPools;
    }

    function deploy(IERC20 token1, IERC20 token2) public returns(Mooniswap pool) {
        require(token1 != token2, "Factory: not support same tokens");
        require(pools[token1][token2] == Mooniswap(0), "Factory: pool already exists");

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token1;
        tokens[1] = token2;

        string memory symbol1 = token1.uniSymbol();
        string memory symbol2 = token2.uniSymbol();

        pool = new Mooniswap(
            string(abi.encodePacked("Mooniswap V1 (", symbol1, "-", symbol2, ")")),
            string(abi.encodePacked("MOON-V1-", symbol1, "-", symbol2))
        );
        pool.setup(tokens);

        pool.transferOwnership(owner());
        pools[token1][token2] = pool;
        pools[token2][token1] = pool;
        allPools.push(pool);
        isPool[pool] = true;

        emit Deployed(
            address(pool),
            address(token1),
            address(token2)
        );
    }
}
