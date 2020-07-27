// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Mooniswap.sol";


contract MooniFactory is Ownable {
    event Deployed(
        address indexed mooniswap,
        address indexed token1,
        address indexed token2
    );

    mapping(address => mapping(address => Mooniswap)) public pools;

    function deploy(address tokenA, address tokenB) external returns(Mooniswap pool) {
        require(tokenA != tokenB, "MooniFactory: do not support equal tokens");

        (address token1, address token2) = _sortTokens(tokenA, tokenB);

        string memory name = string(abi.encodePacked(
            "Mooniswap V1 (",
            ERC20(token1).symbol(),
            "-",
            ERC20(token2).symbol(),
            ")"
        ));

        string memory symbol = string(abi.encodePacked(
            "MOON-V1-",
            ERC20(token1).symbol(),
            "-",
            ERC20(token2).symbol()
        ));

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token1);
        tokens[0] = IERC20(token2);
        pool = new Mooniswap{salt: salt(token1, token2)}(tokens, name, symbol);
        pool.transferOwnership(owner());
        pools[token1][token2] = pool;
        pools[token2][token1] = pool;

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
