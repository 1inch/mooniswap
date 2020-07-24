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

    mapping(address => mapping(address => Mooniswap)) public mooniswaps;

    function deploy(address tokenA, address tokenB) external returns(Mooniswap mooniswap) {
        (address token1, address token2) = _sortTokens(tokenA, tokenB);
        string memory name = string(abi.encodePacked(
            "Mooniswap (",
            ERC20(token1).symbol(),
            "-",
            ERC20(token2).symbol(),
            ")"
        ));

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(token1);
        tokens[0] = IERC20(token2);
        mooniswap = new Mooniswap{salt: salt(token1, token2)}(tokens, name, "MOON-V1");
        mooniswap.transferOwnership(owner());
        mooniswaps[token1][token2] = mooniswap;

        emit Deployed(
            address(mooniswap),
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
