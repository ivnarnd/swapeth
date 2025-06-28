// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
//fuera de remix instalar las dependencias de openzeppelin con node 
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract PascalCoin is ERC20{
    constructor() ERC20("Pascal Coin","PC"){
        _mint(msg.sender,1000);
    }
    receive() external payable { 
        _mint(msg.sender, msg.value);
    }
}