// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Interfaz mínima de un token ERC-20 para interactuar con otros contratos
interface IERC20 {
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
}

// Contrato para crear un pool de intercambio simple tipo Uniswap
contract SimpleSwap {
    struct Pool {
        uint reserveA;
        uint reserveB;
        uint totalLiquidity;
        mapping(address => uint) liquidity;
    }

    mapping(bytes32 => Pool) internal pools;

    function getPoolKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return tokenA < tokenB 
            ? keccak256(abi.encodePacked(tokenA, tokenB)) 
            : keccak256(abi.encodePacked(tokenB, tokenA));
    }

    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Agregar liquidez a un par
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        require(tokenA != tokenB, "Tokens must be different");

        bytes32 key = getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[key];

        (uint reserveA, uint reserveB) = tokenA < tokenB
            ? (pool.reserveA, pool.reserveB)
            : (pool.reserveB, pool.reserveA);

        if (reserveA == 0 && reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint amountAOptimal = (amountBDesired * reserveA) / reserveB;
                require(amountAOptimal <= amountADesired, "Excessive A");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        require(IERC20(tokenA).transferFrom(msg.sender, address(this), amountA), "Transfer tokenA failed");
        require(IERC20(tokenB).transferFrom(msg.sender, address(this), amountB), "Transfer tokenB failed");

        liquidity = pool.totalLiquidity == 0
            ? sqrt(amountA * amountB)
            : min((amountA * pool.totalLiquidity) / reserveA, (amountB * pool.totalLiquidity) / reserveB);

        require(liquidity > 0, "Liquidity must be positive");

        pool.liquidity[msg.sender] += liquidity;
        pool.totalLiquidity += liquidity;

        if (tokenA < tokenB) {
            pool.reserveA += amountA;
            pool.reserveB += amountB;
        } else {
            pool.reserveA += amountB;
            pool.reserveB += amountA;
        }
    }

    // Remover liquidez del pool
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(tokenA != tokenB, "Tokens must be different");

        bytes32 key = getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[key];

        uint userLiquidity = pool.liquidity[msg.sender];
        require(userLiquidity >= liquidity, "Not enough liquidity");

        (uint reserveA, uint reserveB) = tokenA < tokenB
            ? (pool.reserveA, pool.reserveB)
            : (pool.reserveB, pool.reserveA);

        amountA = (liquidity * reserveA) / pool.totalLiquidity;
        amountB = (liquidity * reserveB) / pool.totalLiquidity;

        require(amountA >= amountAMin, "Amount A too low");
        require(amountB >= amountBMin, "Amount B too low");

        pool.liquidity[msg.sender] -= liquidity;
        pool.totalLiquidity -= liquidity;

        if (tokenA < tokenB) {
            pool.reserveA -= amountA;
            pool.reserveB -= amountB;
        } else {
            pool.reserveA -= amountB;
            pool.reserveB -= amountA;
        }

        require(IERC20(tokenA).transfer(to, amountA), "Transfer tokenA failed");
        require(IERC20(tokenB).transfer(to, amountB), "Transfer tokenB failed");
    }

    // Intercambiar un token por otro
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length == 2, "Only 2-token swap allowed");
        require(block.timestamp <= deadline, "Swap expired");
        require(path[0] != path[1], "Tokens must be different");

        bytes32 key = getPoolKey(path[0], path[1]);
        Pool storage pool = pools[key];

        (uint reserveIn, uint reserveOut) = path[0] < path[1]
            ? (pool.reserveA, pool.reserveB)
            : (pool.reserveB, pool.reserveA);

        require(reserveIn > 0 && reserveOut > 0, "No liquidity");

        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn), "Transfer in failed");

        uint amountOut = ((amountIn * 997) * reserveOut) / ((reserveIn * 1000) + (amountIn * 997));
        require(amountOut >= amountOutMin, "Output too low");

        if (path[0] < path[1]) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveA -= amountOut;
            pool.reserveB += amountIn;
        }

        require(IERC20(path[1]).transfer(to, amountOut), "Transfer out failed");

        amounts = new uint [](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        return amounts;
    }

    // Obtener el precio de un token en términos de otro
    function getPrice(address tokenA, address tokenB) external view returns (uint price) {
        bytes32 key = getPoolKey(tokenA, tokenB);
        Pool storage pool = pools[key];

        (uint reserveA, uint reserveB) = tokenA < tokenB
            ? (pool.reserveA, pool.reserveB)
            : (pool.reserveB, pool.reserveA);

        if (reserveA == 0 || reserveB == 0) return 0;

        return (reserveB * 1e18) / reserveA;
    }

    // Calcular cuánto se recibe al hacer un swap
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) external pure returns (uint amountOut) {
        require(amountIn > 0, "amountIn must be > 0");
        require(reserveIn > 0 && reserveOut > 0, "Invalid reserves");

        amountOut = ((amountIn * 997) * reserveOut) / ((reserveIn * 1000) + (amountIn * 997));
    }
}
