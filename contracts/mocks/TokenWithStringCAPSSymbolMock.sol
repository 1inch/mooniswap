// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


contract TokenWithStringCAPSSymbolMock {
    // solhint-disable var-name-mixedcase
    string public SYMBOL = "ABC";

    constructor(string memory s) public {
        SYMBOL = s;
    }
}
