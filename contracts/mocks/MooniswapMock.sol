// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../Mooniswap.sol";


contract FactoryMock is IFactory {
    function fee() external view override returns(uint256) {
        return 0;
    }
}


contract MooniswapMock is Mooniswap {
    constructor(IERC20[] memory assets, string memory name, string memory symbol)
        public Mooniswap(assets, name, symbol)
    {
        factory = new FactoryMock();
    }
}
