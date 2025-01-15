// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IWrappedToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
}

contract WrappedToken_V2 is ERC20, Ownable {
    constructor(
        string memory name, 
        string memory symbol,
        address initialOwner
    ) ERC20(name, symbol) Ownable(initialOwner) {}

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

contract TTBDualWrapper_V2 is Ownable, ReentrancyGuard {
    IERC20 public immutable TTB;
    IWrappedToken public immutable TOKEN_A;
    IWrappedToken public immutable TOKEN_B;
    
    uint256 public immutable RATIO_A;  // How many Token A per 1 TTB
    uint256 public immutable RATIO_B;  // How many Token B per 1 TTB
    address public authorizedMinter;    // Only this address can mint Token B
    
    event AuthorizedMinterSet(address minter);
    event TokenAWrapped(address indexed user, uint256 ttbAmount, uint256 tokenAmount);
    event TokenAUnwrapped(address indexed user, uint256 tokenAmount, uint256 ttbAmount);
    event TokenBMinted(address indexed to, uint256 amount);
    event TokenBUnwrapped(address indexed user, uint256 tokenAmount, uint256 ttbAmount);

    constructor(
        address ttbAddress,
        string memory nameA,
        string memory symbolA,
        string memory nameB,
        string memory symbolB,
        uint256 ratioA,
        uint256 ratioB
    ) Ownable(msg.sender) {
        require(ratioA > 0 && ratioB > 0, "Invalid ratios");
        TTB = IERC20(ttbAddress);
        
        // Deploy token contracts
        WrappedToken tokenA = new WrappedToken(nameA, symbolA, address(this));
        WrappedToken tokenB = new WrappedToken(nameB, symbolB, address(this));
        
        TOKEN_A = IWrappedToken(address(tokenA));
        TOKEN_B = IWrappedToken(address(tokenB));
        
        RATIO_A = ratioA;
        RATIO_B = ratioB;
    }

    function setAuthorizedMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "Invalid minter");
        require(authorizedMinter == address(0), "Minter already set");
        authorizedMinter = _minter;
        emit AuthorizedMinterSet(_minter);
    }

    // Token A functions - Anyone can wrap/unwrap
    function wrapTTB(uint256 ttbAmount) external nonReentrant {
        require(ttbAmount > 0, "Amount must be > 0");
        
        uint256 tokenAmount = ttbAmount * RATIO_A;
        
        require(TTB.transferFrom(msg.sender, address(this), ttbAmount), "TTB transfer failed");
        TOKEN_A.mint(msg.sender, tokenAmount);
        
        emit TokenAWrapped(msg.sender, ttbAmount, tokenAmount);
    }

    function unwrapTokenA(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be > 0");
        
        uint256 ttbAmount = tokenAmount / RATIO_A;
        require(ttbAmount > 0, "TTB amount too small");
        
        TOKEN_A.burn(tokenAmount);
        require(TTB.transfer(msg.sender, ttbAmount), "TTB transfer failed");
        
        emit TokenAUnwrapped(msg.sender, tokenAmount, ttbAmount);
    }

    // Token B functions - Only authorized minter can mint
    function mintTokenB(address to, uint256 amount) external nonReentrant {
        require(msg.sender == authorizedMinter, "Only authorized minter");
        require(amount > 0, "Amount must be > 0");
        
        uint256 ttbNeeded = (amount + RATIO_B - 1) / RATIO_B;
        
        require(TTB.transferFrom(msg.sender, address(this), ttbNeeded), "TTB transfer failed");
        TOKEN_B.mint(to, amount);
        
        emit TokenBMinted(to, amount);
    }

    function unwrapTokenB(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be > 0");
        
        uint256 ttbAmount = tokenAmount / RATIO_B;
        require(ttbAmount > 0, "TTB amount too small");
        
        TOKEN_B.burn(tokenAmount);
        require(TTB.transfer(msg.sender, ttbAmount), "TTB transfer failed");
        
        emit TokenBUnwrapped(msg.sender, tokenAmount, ttbAmount);
    }
}