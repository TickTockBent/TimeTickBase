pragma solidity ^0.8.28;

import "./TimeTickBase.sol";

contract ReentrancyMock {
    TimeTickBase public ttb;
    bool public attacking;
    
    constructor(address _ttb) {
        ttb = TimeTickBase(_ttb);
    }
    
    function attackStake() external {
        attacking = true;
        ttb.stake(3600 ether);
        attacking = false;
    }
    
    function onERC20Received(address, uint256) external returns (bool) {
        if (attacking) {
            ttb.stake(3600 ether);
        }
        return true;
    }
}