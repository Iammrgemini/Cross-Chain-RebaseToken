# Cross-chain Rebase Token

1. A protocol that allow users to deposit into a vault and in turn, receive rebase token that represent their underlying balance 
2. Rebase token -> balanceOf function is dynamic to show the changing balance with time.
     - Balance increases linearly with time
     - mint tokens to our users every time they perform an action by (minting, burning , transferring, or .... bridging) 
3. Interest rate
     - Individually set an interest rate of each user based on some global interest rate of the protocol at the time the user deposit into the vault.
     - This global interest rate can only decrease to incentivide/reward early adopters.
     - Increase token adoption!