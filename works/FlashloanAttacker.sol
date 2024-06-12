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
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./OtherContracts.sol";
import "./IAlgebraPoolState.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "https://github.com/cryptoalgebra/Algebra/blob/master/src/core/contracts/interfaces/IAlgebraFactory.sol";

// POOL PROVIDER FOR CONSTRUCTOR: 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb
// 0x0000000000000000000000000000000000001010 MATIC


contract FlashloanAttacker is FlashLoanSimpleReceiverBase {
    using GPv2SafeERC20 for IERC20;
    using SafeMath for uint256;

    IPoolAddressesProvider internal _provider;
    IPool internal _pool;
    address payable owner;
    address public swapTo = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    uint256 public amountOutV2 = 0;
    address public routerAddressV2 = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    IUniswapV2Router02 public immutable swapRouterV2 = IUniswapV2Router02(routerAddressV2);
    address public routerAddressV3 = 0xf5b509bB0909a69B1c207E495f687a596C168E12;
    ISwapRouter public immutable swapRouter = ISwapRouter(routerAddressV3);
    address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    IAlgebraFactory public v3factory = IAlgebraFactory(0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28);
    IUniswapV2Factory public v2factory = IUniswapV2Factory(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32);
    // bool public v2tov3Swap = false;



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


    function swapExactInputSingle(address _token, address _tokenOut, uint256 amountIn) public returns (uint256 amountOut) {  
        IERC20 token = IERC20(_token);
        token.approve(address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _token,
                tokenOut: _tokenOut,
                recipient: address(this), // solved big errors also amountIn should be max DAI
                deadline: block.timestamp + 300, //5 MINUTES DEADLINE 
                amountIn: amountIn,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            });
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapUniV2(address _fromToken, address _toToken, uint256 amountIn) public returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = _fromToken;
        path[1] = _toToken;
        // preApprove(_fromToken, amountIn, routerAddressV2);
         IERC20 token = IERC20(_fromToken);
        token.approve(routerAddressV2, amountIn);
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
        swapExactInputSingle(asset, 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, amount);
        uint256 toBalance = IERC20(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6).balanceOf(address(this));
        swapUniV2(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6, asset, toBalance);
        IERC20(asset).approve(address(POOL), amount.add(premium));
      return true;
    }

    // function flashAttack(address usdctoken, address to, uint256 toDecimals, uint256 _amount, uint256 _amountOut) external onlyOwner {
    //     swapTo = to;
    //     amountOutV2 = _amountOut;
    //     uint256 v2price = getV2TokenPrice(to, usdctoken, toDecimals);
    //     uint256 v3price = getV3TokenPrice(to, usdctoken, toDecimals);
    //     if(v2price < v3price) {
    //       v2tov3Swap = true;
    //     } else {
    //       v2tov3Swap = false;
    //     }
    //     // requestFlashLoan(usdctoken, _amount);
    // }


    function getBalance(address _tokenAddress) public view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }

    function withdraw(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = IERC20(_tokenAddress).balanceOf(address(this));
        token.transfer(address(msg.sender), balance);
    }


    // function getV3TokenPrice(address token, address usdcToken, uint256 decimals) public view returns (uint256 price) {
    //     address poolAddress = v3factory.poolByPair(token, usdcToken);
    //     require(poolAddress != address(0), "Pool does not exist");
        
    //     IAlgebraPoolState pool = IAlgebraPoolState(poolAddress);
    //     (uint160 sqrtPriceX96,,,,,,) = pool.globalState();
        
    //     // Convert the sqrtPriceX96 to a human-readable price
    //     uint256 sqrtPriceX96Squared = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
    //     uint256 priceRaw = sqrtPriceX96Squared / (1 << 192);
        
    //     // Assuming the price is token per USDC, and converting it to a standard decimal format
    //     price = (1* (10 ** decimals)) / priceRaw;
    //     return price;
    // }

    // function getV2TokenPrice(address token, address usdcToken, uint256 decimals) public view returns (uint256 price) {
    //     address pairAddress = v2factory.getPair(token, usdcToken);
    //     require(pairAddress != address(0), "Pool does not exist");
        
    //     IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
    //     (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
    //     address token0 = pair.token0();
    //     // address token1 = pair.token1();
        
    //     if (token0 == USDC) {
    //         // token0 is USDC, token1 is the target token
    //         price = (reserve0 * (10 ** decimals)) / reserve1; // price of token in terms of USDC
    //     } else {
    //         // token1 is USDC, token0 is the target token
    //         price = (reserve1 * (10 ** decimals)) / reserve0; // price of token in terms of USDC
    //     }

    //     return price;
    // }

}

contract ConvertUint8ToUint256 {
    function convert(uint8 value) public pure returns (uint256) {
        return uint256(value);
    }
}
