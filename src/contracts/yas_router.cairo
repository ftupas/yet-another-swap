use starknet::ContractAddress;

use yas::numbers::signed_integer::{i32::i32, i256::i256};
use yas::numbers::fixed_point::implementations::impl_64x96::FixedType;

#[starknet::interface]
trait IYASRouter<TContractState> {
    fn mint(
        self: @TContractState,
        pool: ContractAddress,
        recipient: ContractAddress,
        tick_lower: i32,
        tick_upper: i32,
        amount: u128
    ) -> (u256, u256);
    fn create_limit_order(
        self: @TContractState,
        pool: ContractAddress,
        recipient: ContractAddress,
        tick_lower: i32,
        amount: u128,
    );
    fn collect_limit_order(
        self: @TContractState, pool: ContractAddress, recipient: ContractAddress, tick_lower: i32,
    );
    fn yas_mint_callback(
        ref self: TContractState, amount_0_owed: u256, amount_1_owed: u256, data: Array<felt252>
    );
    fn yas_collect_callback(
        ref self: TContractState,
        amount_0_collected: u256,
        amount_1_collected: u256,
        data: Array<felt252>
    );
    fn swap(
        self: @TContractState,
        pool: ContractAddress,
        recipient: ContractAddress,
        zero_for_one: bool,
        amount_specified: i256,
        sqrt_price_limit_X96: FixedType
    ) -> (i256, i256);
    fn yas_swap_callback(
        ref self: TContractState, amount_0_delta: i256, amount_1_delta: i256, data: Array<felt252>
    );
    fn swap_exact_0_for_1(
        self: @TContractState,
        pool: ContractAddress,
        amount_in: u256,
        recipient: ContractAddress,
        sqrt_price_limit_X96: FixedType
    ) -> (i256, i256);
    fn swap_exact_1_for_0(
        self: @TContractState,
        pool: ContractAddress,
        amount_in: u256,
        recipient: ContractAddress,
        sqrt_price_limit_X96: FixedType
    ) -> (i256, i256);
}

#[starknet::contract]
mod YASRouter {
    use super::IYASRouter;

    use starknet::{ContractAddress, get_caller_address, get_contract_address};

    use yas::contracts::yas_pool::{IYASPoolDispatcher, IYASPoolDispatcherTrait};
    use yas::interfaces::interface_ERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use yas::numbers::fixed_point::implementations::impl_64x96::FixedType;
    use yas::numbers::signed_integer::{i32::i32, i256::i256, integer_trait::IntegerTrait};
    use debug::PrintTrait;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MintCallback: MintCallback,
        SwapCallback: SwapCallback,
        CollectCallback: CollectCallback,
    }

    #[derive(Drop, starknet::Event)]
    struct MintCallback {
        amount_0_owed: u256,
        amount_1_owed: u256
    }

    #[derive(Drop, starknet::Event)]
    struct CollectCallback {
        amount_0_collected: u256,
        amount_1_collected: u256
    }

    #[derive(Drop, starknet::Event)]
    struct SwapCallback {
        amount_0_delta: i256,
        amount_1_delta: i256
    }

    #[storage]
    struct Storage {}

    #[external(v0)]
    impl YASRouterCallbackImpl of IYASRouter<ContractState> {
        fn mint(
            self: @ContractState,
            pool: ContractAddress,
            recipient: ContractAddress,
            tick_lower: i32,
            tick_upper: i32,
            amount: u128
        ) -> (u256, u256) {
            IYASPoolDispatcher { contract_address: pool }
                .mint(
                    recipient, tick_lower, tick_upper, amount, array![get_caller_address().into()]
                )
        }

        fn create_limit_order(
            self: @ContractState,
            pool: ContractAddress,
            recipient: ContractAddress,
            tick_lower: i32,
            amount: u128,
        ) {
            IYASPoolDispatcher { contract_address: pool }
                .create_limit_order(
                    recipient, tick_lower, amount, array![get_caller_address().into()]
                );
        }

        fn collect_limit_order(
            self: @ContractState,
            pool: ContractAddress,
            recipient: ContractAddress,
            tick_lower: i32,
        ) {
            IYASPoolDispatcher { contract_address: pool }
                .collect_limit_order(recipient, tick_lower, array![get_caller_address().into()]);
        }

        fn yas_mint_callback(
            ref self: ContractState, amount_0_owed: u256, amount_1_owed: u256, data: Array<felt252>
        ) {
            let msg_sender = get_caller_address();

            // TODO: we need verify if data has a valid ContractAddress
            let mut sender: ContractAddress = Zeroable::zero();
            if !data.is_empty() {
                sender = (*data[0]).try_into().unwrap();
            }

            self.emit(MintCallback { amount_0_owed, amount_1_owed });

            if amount_0_owed > 0 {
                let token_0 = IYASPoolDispatcher { contract_address: msg_sender }.token_0();
                IERC20Dispatcher { contract_address: token_0 }
                    .transferFrom(sender, msg_sender, amount_0_owed);
            }
            if amount_1_owed > 0 {
                let token_1 = IYASPoolDispatcher { contract_address: msg_sender }.token_1();
                IERC20Dispatcher { contract_address: token_1 }
                    .transferFrom(sender, msg_sender, amount_1_owed);
            }
        }

        fn yas_collect_callback(
            ref self: ContractState,
            amount_0_collected: u256,
            amount_1_collected: u256,
            data: Array<felt252>
        ) {
            let msg_sender = get_caller_address();

            // TODO: we need verify if data has a valid ContractAddress
            let mut receipient: ContractAddress = Zeroable::zero();
            if !data.is_empty() {
                receipient = (*data[0]).try_into().unwrap();
            }

            self.emit(CollectCallback { amount_0_collected, amount_1_collected });

            // Send the collected tokens to the receipient
            if amount_0_collected > 0 {
                let token_0 = IYASPoolDispatcher { contract_address: msg_sender }.token_0();
                IERC20Dispatcher { contract_address: token_0 }
                    .transferFrom(msg_sender, receipient, amount_0_collected);
            }
            if amount_1_collected > 0 {
                let token_1 = IYASPoolDispatcher { contract_address: msg_sender }.token_1();
                IERC20Dispatcher { contract_address: token_1 }
                    .transferFrom(msg_sender, receipient, amount_1_collected);
            }
        }

        fn swap(
            self: @ContractState,
            pool: ContractAddress,
            recipient: ContractAddress,
            zero_for_one: bool,
            amount_specified: i256,
            sqrt_price_limit_X96: FixedType
        ) -> (i256, i256) {
            IYASPoolDispatcher { contract_address: pool }
                .swap(
                    recipient,
                    zero_for_one,
                    amount_specified,
                    sqrt_price_limit_X96,
                    array![get_caller_address().into()]
                )
        }

        fn yas_swap_callback(
            ref self: ContractState,
            amount_0_delta: i256,
            amount_1_delta: i256,
            data: Array<felt252>
        ) {
            let msg_sender = get_caller_address();

            // TODO: we need verify if data has a valid ContractAddress
            let mut sender: ContractAddress = Zeroable::zero();
            if !data.is_empty() {
                sender = (*data[0]).try_into().unwrap();
            }

            self.emit(SwapCallback { amount_0_delta, amount_1_delta });

            if amount_0_delta > Zeroable::zero() {
                let token_0 = IYASPoolDispatcher { contract_address: msg_sender }.token_0();
                IERC20Dispatcher { contract_address: token_0 }
                    .transferFrom(sender, msg_sender, amount_0_delta.try_into().unwrap());
            } else if amount_1_delta > Zeroable::zero() {
                let token_1 = IYASPoolDispatcher { contract_address: msg_sender }.token_1();
                IERC20Dispatcher { contract_address: token_1 }
                    .transferFrom(sender, msg_sender, amount_1_delta.try_into().unwrap());
            } else {
                // if both are not gt 0, both must be 0.
                assert(
                    amount_0_delta == Zeroable::zero() && amount_1_delta == Zeroable::zero(),
                    'both amount deltas are negative'
                );
            }
        }
        fn swap_exact_0_for_1(
            self: @ContractState,
            pool: ContractAddress,
            amount_in: u256,
            recipient: ContractAddress,
            sqrt_price_limit_X96: FixedType
        ) -> (i256, i256) {
            IYASPoolDispatcher { contract_address: pool }
                .swap(
                    recipient,
                    true,
                    IntegerTrait::<i256>::new(amount_in, false),
                    sqrt_price_limit_X96,
                    array![get_caller_address().into()]
                )
        }

        fn swap_exact_1_for_0(
            self: @ContractState,
            pool: ContractAddress,
            amount_in: u256,
            recipient: ContractAddress,
            sqrt_price_limit_X96: FixedType
        ) -> (i256, i256) {
            IYASPoolDispatcher { contract_address: pool }
                .swap(
                    recipient,
                    true,
                    IntegerTrait::<i256>::new(amount_in, true),
                    sqrt_price_limit_X96,
                    array![get_caller_address().into()]
                )
        }
    }
}
