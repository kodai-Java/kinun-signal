use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DcfInput {
    pub cash_and_equivalents: f64, // 現金及び短期投資 (ドル)
    pub total_debt: f64,           // 有利子負債合計 (ドル)
    pub free_cash_flow: f64,       // 直近の基準FCF (ドル)
    pub shares_outstanding: f64,   // 希薄化後発行済株式数 (株)
    pub wacc: f64,                 // 割引率 (例: 0.085 = 8.5%)
    pub growth_rate_base: f64,     // 基本シナリオ成長率 (例: 0.12 = 12%)
    pub growth_rate_bull: f64,     // 強気シナリオ成長率 (例: 0.18 = 18%)
    pub growth_rate_bear: f64,     // 弱気シナリオ成長率 (例: 0.06 = 6%)
    pub terminal_growth_rate: f64, // 永久成長率 (例: 0.025 = 2.5%)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DcfOutput {
    pub net_cash: f64,
    pub base_price: f64,
    pub bull_price: f64,
    pub bear_price: f64,
}

pub fn calculate(input: &DcfInput) -> DcfOutput {
    let net_cash = input.cash_and_equivalents - input.total_debt;

    if input.shares_outstanding <= 0.0 {
        return DcfOutput {
            net_cash,
            base_price: 0.0,
            bull_price: 0.0,
            bear_price: 0.0,
        };
    }

    let base_price = calculate_scenario_price(
        net_cash,
        input.free_cash_flow,
        input.shares_outstanding,
        input.wacc,
        input.growth_rate_base,
        input.terminal_growth_rate,
    );
    let bull_price = calculate_scenario_price(
        net_cash,
        input.free_cash_flow,
        input.shares_outstanding,
        input.wacc,
        input.growth_rate_bull,
        input.terminal_growth_rate,
    );
    let bear_price = calculate_scenario_price(
        net_cash,
        input.free_cash_flow,
        input.shares_outstanding,
        input.wacc,
        input.growth_rate_bear,
        input.terminal_growth_rate,
    );

    DcfOutput {
        net_cash,
        base_price,
        bull_price,
        bear_price,
    }
}

fn calculate_scenario_price(
    net_cash: f64,
    free_cash_flow: f64,
    shares_outstanding: f64,
    wacc: f64,
    g: f64,
    terminal_growth_rate: f64,
) -> f64 {
    let ev = if free_cash_flow <= 0.0 {
        0.0
    } else {
        let r = wacc.max(0.04);
        let g_t = terminal_growth_rate.min(r - 0.015).max(0.0);

        let pv_fcf: f64 = (1..=5)
            .map(|t| (free_cash_flow * (1.0 + g).powi(t)) / (1.0 + r).powi(t))
            .sum();

        let fcf_5 = free_cash_flow * (1.0 + g).powi(5);
        let tv = (fcf_5 * (1.0 + g_t)) / (r - g_t);
        let pv_tv = tv / (1.0 + r).powi(5);

        pv_fcf + pv_tv
    };

    let price = ((net_cash + ev) / shares_outstanding).max(0.0);
    round_two_decimals(price)
}

pub fn calculate_divergence_rate(current_price: f64, base_price: f64) -> f64 {
    if base_price <= 0.0 {
        return 0.0;
    }
    let rate = ((current_price - base_price) / base_price) * 100.0;
    round_two_decimals(rate)
}

pub fn is_undervalued(current_price: f64, base_price: f64, target_discount_rate: f64) -> bool {
    if base_price <= 0.0 {
        return false;
    }
    current_price <= base_price * (1.0 - target_discount_rate / 100.0)
}

pub fn round_two_decimals(val: f64) -> f64 {
    (val * 100.0).round() / 100.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dcf_standard_calculation() {
        let input = DcfInput {
            cash_and_equivalents: 65_000_000_000.0,
            total_debt: 105_000_000_000.0,
            free_cash_flow: 108_000_000_000.0,
            shares_outstanding: 15_200_000_000.0,
            wacc: 0.085,
            growth_rate_base: 0.11,
            growth_rate_bull: 0.16,
            growth_rate_bear: 0.06,
            terminal_growth_rate: 0.025,
        };

        let out = calculate(&input);
        assert_eq!(out.net_cash, -40_000_000_000.0);
        assert!(out.bull_price > out.base_price);
        assert!(out.base_price > out.bear_price);
        assert!(out.bear_price > 0.0);
    }

    #[test]
    fn test_dcf_zero_shares_guard() {
        let input = DcfInput {
            cash_and_equivalents: 1000.0,
            total_debt: 200.0,
            free_cash_flow: 500.0,
            shares_outstanding: 0.0,
            wacc: 0.08,
            growth_rate_base: 0.10,
            growth_rate_bull: 0.15,
            growth_rate_bear: 0.05,
            terminal_growth_rate: 0.02,
        };

        let out = calculate(&input);
        assert_eq!(out.base_price, 0.0);
        assert_eq!(out.bull_price, 0.0);
        assert_eq!(out.bear_price, 0.0);
    }

    #[test]
    fn test_dcf_negative_fcf_uses_asset_value_only() {
        let input = DcfInput {
            cash_and_equivalents: 5000.0,
            total_debt: 1000.0,
            free_cash_flow: -200.0,
            shares_outstanding: 100.0,
            wacc: 0.08,
            growth_rate_base: 0.10,
            growth_rate_bull: 0.20,
            growth_rate_bear: 0.05,
            terminal_growth_rate: 0.02,
        };

        let out = calculate(&input);
        // net_cash = 4000, ev = 0, shares = 100 -> price = 40.0
        assert_eq!(out.net_cash, 4000.0);
        assert_eq!(out.base_price, 40.0);
        assert_eq!(out.bull_price, 40.0);
        assert_eq!(out.bear_price, 40.0);
    }

    #[test]
    fn test_dcf_wacc_and_terminal_growth_guards() {
        let input = DcfInput {
            cash_and_equivalents: 1000.0,
            total_debt: 0.0,
            free_cash_flow: 100.0,
            shares_outstanding: 10.0,
            wacc: 0.01,                 // Should be clamped to 0.04
            growth_rate_base: 0.05,
            growth_rate_bull: 0.08,
            growth_rate_bear: 0.02,
            terminal_growth_rate: 0.10, // Should be clamped to r - 0.015 = 0.025
        };

        let out = calculate(&input);
        assert!(out.base_price.is_finite());
        assert!(out.base_price > 0.0);
    }

    #[test]
    fn test_divergence_and_undervalued() {
        let div = calculate_divergence_rate(150.0, 200.0);
        assert_eq!(div, -25.0);
        assert!(is_undervalued(150.0, 200.0, 20.0));
        assert!(!is_undervalued(170.0, 200.0, 20.0));
    }
}
