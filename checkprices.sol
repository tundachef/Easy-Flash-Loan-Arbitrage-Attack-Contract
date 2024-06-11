/*

 ██████  ██████   ██████  ██   ██ ██████   ██████   ██████  ██   ██    ██████  ███████ ██    ██
██      ██    ██ ██    ██ ██  ██  ██   ██ ██    ██ ██    ██ ██  ██     ██   ██ ██      ██    ██
██      ██    ██ ██    ██ █████   ██████  ██    ██ ██    ██ █████      ██   ██ █████   ██    ██
██      ██    ██ ██    ██ ██  ██  ██   ██ ██    ██ ██    ██ ██  ██     ██   ██ ██       ██  ██
 ██████  ██████   ██████  ██   ██ ██████   ██████   ██████  ██   ██ ██ ██████  ███████   ████

Find any smart contract, and build your project faster: https://www.cookbook.dev/?utm=code
Twitter: https://twitter.com/cookbook_dev
Discord: https://discord.gg/cookbookdev

Find this contract on Cookbook: https://www.cookbook.dev/contracts/FlashloanAttacker?utm=code

PLEASE DO NOT DEPLOY ON A MAINNET, ONLY ON A TESTNET
NET2DEV NOR COOKBOOK.DEV WILL NOT ASSUME ANY RESPONSIBILITY FOR ANY USE, LOSS OF FUNDS OR ANY OTHER ISSUES.
*/

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {SafeMath} from '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import {GPv2SafeERC20} from '../../dependencies/gnosis/contracts/GPv2SafeERC20.sol';
import {IPoolAddressesProvider} from '../../interfaces/IPoolAddressesProvider.sol';
import {FlashLoanSimpleReceiverBase} from '../../flashloan/base/FlashLoanSimpleReceiverBase.sol';
import {MintableERC20} from '../tokens/MintableERC20.sol';
import {IPool} from '../../interfaces/IPool.sol';
import {DataTypes} from '../../protocol/libraries/types/DataTypes.sol';
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "https://github.com/cryptoalgebra/Algebra/blob/master/src/core/contracts/interfaces/IAlgebraFactory.sol";
import "./IAlgebraPoolState.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract FlashloanAttacker is FlashLoanSimpleReceiverBase {
  using GPv2SafeERC20 for IERC20;
  using SafeMath for uint256;

  IPoolAddressesProvider internal _provider;
  IPool internal _pool;
  address payable owner;
  address public swapTo;
  uint256 public amountOutV2;
  address public routerAddressV2 = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
  IUniswapV2Router02 public immutable swapRouterV2 = IUniswapV2Router02(routerAddressV2);
  address public routerAddressV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  ISwapRouter public immutable swapRouterV3 = ISwapRouter(routerAddressV3);

    IUniswapV3Factory public v3factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    IUniswapV2Factory public v2factory = IUniswapV2Factory(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32);
    bool public v2tov3Swap = true;


  constructor(IPoolAddressesProvider provider) FlashLoanSimpleReceiverBase(provider) {
    _pool = IPool(provider.getPool());
    owner = payable(msg.sender);
  }

  modifier onlyOwner() {
    require(address(msg.sender) == owner, "Access Denied");
    _;
  }

  function preApprove(address _token, uint256 amount, address routerAddress) internal {
        IERC20 token = IERC20(_token);
        token.approve(address(routerAddress), amount);
  }

  function requestFlashLoan(address _token, uint256 _amount) public {
    address receiverAddress = address(this);
    address asset = _token;
    uint256 amount = _amount;
    bytes memory params = "";
    uint16 referralCode = 0;

    POOL.flashLoanSimple(
        receiverAddress,
        asset,
        amount,
        params,
        referralCode
        );
  }

    function swapExactInputSingle(
        address from,
        address to,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        uint24 poolFee = 3000;
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: from,
                tokenOut: to,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        amountOut = swapRouterV3.exactInputSingle(params);
    }
  
    function swapUniV2(address _fromToken, address _toToken, uint256 amountIn) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _fromToken;
        path[1] = _toToken;
        uint256 amountReceived = swapRouterV2.swapExactTokensForTokens(amountIn, amountOutV2, path, address(this), block.timestamp)[1];
        require(amountReceived > 0, "Aborted Tx: Trade returned zero");
        return amountReceived;
    }


    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address, // initiator
        bytes memory // params
    ) public override returns (bool) {
        if(v2tov3Swap) {
            // 
            preApprove(asset, amount, routerAddressV2); //Approve First Swap
            swapUniV2(asset, swapTo, amount); //First Swap UniswapV3 BUY TOKEN
            uint256 toBalance = IERC20(swapTo).balanceOf(address(this)); //Get New Token Balance
            preApprove(swapTo, toBalance, routerAddressV3); //Approve Second Swap UniswapV2 SELL TOKEN
            swapExactInputSingle(swapTo, asset, toBalance); //Second Swap
        } else {
            // 
            preApprove(asset, amount, routerAddressV3); //Approve First Swap
            swapExactInputSingle(asset, swapTo, amount); //First Swap UniswapV3 BUY TOKEN
            uint256 toBalance = IERC20(swapTo).balanceOf(address(this)); //Get New Token Balance
            preApprove(swapTo, toBalance, routerAddressV2); //Approve Second Swap UniswapV2 SELL TOKEN
            swapUniV2(swapTo, asset, toBalance); //Second Swap
        }

        uint256 finalBalance = IERC20(asset).balanceOf(address(this));
        require(finalBalance >= amount.add(premium), "Repayment amount insufficient");

        IERC20(asset).approve(address(POOL), amount.add(premium));
        return true;
            
    }

    function flashAttack(address _token, address to, uint256 _amount, uint256 _amountOut) external onlyOwner {
        swapTo = to;
        amountOutV2 = _amountOut;
        requestFlashLoan(_token, _amount);
    }


    function flashRun(uint256 _amount) external onlyOwner {
        address tweth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // weth address polygon
        swapTo = tweth;
        uint256 v3price = getV3TokenPrice(tweth);
        uint256 v2price = getV2TokenPrice(tweth);
        if(v2price > v3price) {
            v2tov3Swap = false;
        }
        if(v2price == v3price) {
            return;
        }
        if(v2price < v3price) {
            v2tov3Swap = true;
        }

        amountOutV2 = 1;
        requestFlashLoan(usdc, _amount);
    }


    function getBalance(address _tokenAddress) public view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function withdraw(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = IERC20(_tokenAddress).balanceOf(address(this));
        token.transfer(address(msg.sender), balance);
    }


    function getV3TokenPrice(address token) public view returns (uint256 price) {
        address poolAddress = v3factory.getPool(token, usdc, 3000);
        require(poolAddress != address(0), "Pool does not exist");
        
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        
        // Convert the sqrtPriceX96 to a human-readable price
        
        uint256 sqrtPriceX96Squared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 priceRaw = sqrtPriceX96Squared / (1 << 192);
        
        // Assuming the price is token per WETH, and converting it to a standard decimal format
        price = (1e18) / priceRaw;
        return price;
    }


    function getV2TokenPrice(address token) public view returns (uint256 price) {
        address pairAddress = v2factory.getPair(token, usdc);
        require(pairAddress != address(0), "Pool does not exist");
        
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
        address token0 = pair.token0();
        // address token1 = pair.token1();
        
        if (token0 == usdc) {
            // token0 is WETH, token1 is the target token
            price = (reserve0 * 1e18) / reserve1; // price of token in terms of WETH
        } else {
            // token1 is WETH, token0 is the target token
            price = (reserve1 * 1e18) / reserve0; // price of token in terms of WETH
        }
    }

}

contract UniswapV3PriceFetcher {
    IUniswapV3Factory public factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    function getV3TokenPrice(address token) external view returns (uint256 price) {
        address poolAddress = factory.getPool(token, usdc, 3000);
        require(poolAddress != address(0), "Pool does not exist");
        
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        
        // Convert the sqrtPriceX96 to a human-readable price
        
        uint256 sqrtPriceX96Squared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 priceRaw = sqrtPriceX96Squared / (1 << 192);
        
        // Assuming the price is token per WETH, and converting it to a standard decimal format
        price = (1e18) / priceRaw;
        return price;
    }
}


contract QuickSwapV2PriceFetcher {
    IUniswapV2Factory public factory = IUniswapV2Factory(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32);
    address public weth = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    function getV2TokenPrice(address token) external view returns (uint256 price) {
        address pairAddress = factory.getPair(token, weth);
        require(pairAddress != address(0), "Pool does not exist");
        
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
        address token0 = pair.token0();
        // address token1 = pair.token1();
        
        if (token0 == weth) {
            // token0 is WETH, token1 is the target token
            price = (reserve0 * 1e18) / reserve1; // price of token in terms of WETH
        } else {
            // token1 is WETH, token0 is the target token
            price = (reserve1 * 1e18) / reserve0; // price of token in terms of WETH
        }
    }
}


contract AlgebraV3PriceFetcher {
    IAlgebraFactory public factory = IAlgebraFactory(0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28);
    address public usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    function getV3TokenPrice(address token) external view returns (uint256 price) {
        address poolAddress = factory.poolByPair(token, usdc);
        require(poolAddress != address(0), "Pool does not exist");
        
        IAlgebraPoolState pool = IAlgebraPoolState(poolAddress);
        (uint160 sqrtPriceX96,,,,,,) = pool.globalState();
        
        // Convert the sqrtPriceX96 to a human-readable price
        uint256 sqrtPriceX96Squared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 priceRaw = sqrtPriceX96Squared / (1 << 192);
        
        // Assuming the price is token per USDC, and converting it to a standard decimal format
        price = (1e18) / priceRaw;
        return price;
    }
}
