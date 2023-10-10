mod LiquidityError {
    fn ZeroLiquidity() {
        panic(array!['no liquidity'])
    }
}

mod RangeError {
    fn InRange() {
        panic(array!['in range'])
    }
}
