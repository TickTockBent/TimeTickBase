// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TTBDualWrapper
 * @dev Canonical pattern for wrapping TTB into two different tokens with different properties.
 * Token A: Direct wrapper with configurable ratio
 * Token B: Controlled wrapper with separate ratio and restricted minting
 */
contract TTBDualWrapper is Ownable, ReentrancyGuard {
    IERC20 public immutable TTB;
    ERC20 public immutable TOKEN_A;
    ERC20 public immutable TOKEN_B;
    
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
    ) {
        require(ratioA > 0 && ratioB > 0, "Invalid ratios");
        TTB = IERC20(ttbAddress);
        TOKEN_A = new WrappedToken(nameA, symbolA);
        TOKEN_B = new WrappedToken(nameB, symbolB);
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
        require(TOKEN_A.mint(msg.sender, tokenAmount), "Mint failed");
        
        emit TokenAWrapped(msg.sender, ttbAmount, tokenAmount);
    }

    function unwrapTokenA(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Amount must be > 0");
        require(tokenAmount % RATIO_A == 0, "Must unwrap in whole units");
        
        uint256 ttbAmount = tokenAmount / RATIO_A;
        
        require(TOKEN_A.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
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
        require(TOKEN_B.mint(to, amount), "Mint failed");
        
        emit TokenBMinted(to, amount);
    }

    function unwrapTokenB(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount >= RATIO_B, "Must unwrap minimum amount");
        require(tokenAmount % RATIO_B == 0, "Must unwrap in whole units");
        
        uint256 ttbAmount = tokenAmount / RATIO_B;
        
        require(TOKEN_B.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        TOKEN_B.burn(tokenAmount);
        
        require(TTB.transfer(msg.sender, ttbAmount), "TTB transfer failed");
        
        emit TokenBUnwrapped(msg.sender, tokenAmount, ttbAmount);
    }
}

/**
 * @title WrappedToken
 * @dev Simple ERC20 that can only be minted/burned by the wrapper
 */
contract WrappedToken is ERC20 {
    address public immutable wrapper;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        wrapper = msg.sender;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        require(msg.sender == wrapper, "Only wrapper can mint");
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        require(msg.sender == wrapper, "Only wrapper can burn");
        _burn(msg.sender, amount);
    }
}