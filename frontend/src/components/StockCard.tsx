"use client";

import React from "react";
import {
  ArrowDownRight,
  ArrowUpRight,
  ChevronRight,
  Sparkles,
  Target,
} from "lucide-react";
import { WatchlistItem } from "@/types/stock";

interface StockCardProps {
  stock: WatchlistItem;
  onSelect: (ticker: string) => void;
}

export default function StockCard({ stock, onSelect }: StockCardProps) {
  const maxBarPrice = Math.max(
    stock.bull_price,
    stock.base_price,
    stock.bear_price,
    stock.current_price,
    1
  );

  const bullWidth = Math.min(100, Math.max(12, (stock.bull_price / maxBarPrice) * 100));
  const baseWidth = Math.min(100, Math.max(12, (stock.base_price / maxBarPrice) * 100));
  const bearWidth = Math.min(100, Math.max(12, (stock.bear_price / maxBarPrice) * 100));

  const isDiscount = stock.divergence_rate < 0;
  const reasoningPreview =
    stock.reasoning_ja.length > 100
      ? `${stock.reasoning_ja.slice(0, 100)}...`
      : stock.reasoning_ja;

  return (
    <div
      onClick={() => onSelect(stock.ticker)}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect(stock.ticker);
        }
      }}
      className={`group relative flex flex-col justify-between rounded-xl border p-5 transition-all duration-200 cursor-pointer ${
        stock.is_undervalued_alert
          ? "border-emerald-500/90 bg-slate-900/95 shadow-[0_0_25px_-5px_rgba(16,185,129,0.35)] hover:border-emerald-400"
          : "border-slate-800 bg-slate-900/90 hover:border-slate-700 hover:bg-slate-900"
      }`}
    >
      {/* Top Row: Ticker, Company & Alert / Divergence Badges */}
      <div>
        <div className="flex items-start justify-between gap-2">
          <div>
            <div className="flex items-center gap-2">
              <span className="font-mono text-xl font-extrabold tracking-tight text-white">
                {stock.ticker}
              </span>
              <span className="rounded border border-slate-700 bg-slate-800/80 px-1.5 py-0.5 font-mono text-[11px] text-slate-300">
                目標割安率 -{stock.target_discount_rate.toFixed(0)}%
              </span>
            </div>
            <p className="mt-0.5 text-xs font-medium text-slate-400 line-clamp-1">
              {stock.company_name}
            </p>
          </div>

          {/* Divergence Badge */}
          <div
            className={`inline-flex items-center gap-1 rounded-md border px-2.5 py-1 font-mono text-xs font-bold ${
              isDiscount
                ? "border-emerald-500/40 bg-emerald-500/15 text-emerald-300"
                : "border-amber-500/40 bg-amber-500/15 text-amber-300"
            }`}
          >
            {isDiscount ? (
              <ArrowDownRight className="h-3.5 w-3.5" />
            ) : (
              <ArrowUpRight className="h-3.5 w-3.5" />
            )}
            <span>
              {stock.divergence_rate > 0 ? "+" : ""}
              {stock.divergence_rate.toFixed(2)}%
            </span>
          </div>
        </div>

        {/* Undervalued Target Reached Badge */}
        {stock.is_undervalued_alert && (
          <div className="mt-3 flex items-center gap-1.5 rounded-lg border border-emerald-500/50 bg-emerald-500/15 px-3 py-1.5 text-xs font-semibold text-emerald-300">
            <Target className="h-4 w-4 shrink-0 text-emerald-400 animate-pulse" />
            <span>🎯 買い圏内 (目標割安率達成)</span>
          </div>
        )}

        {/* Price Comparison Header */}
        <div className="mt-4 grid grid-cols-2 gap-3 rounded-lg border border-slate-800/90 bg-slate-950/60 p-3">
          <div>
            <span className="text-[11px] font-medium uppercase tracking-wider text-slate-400">
              現在株価 (Close)
            </span>
            <div className="mt-0.5 font-mono text-xl font-bold text-slate-100">
              ${stock.current_price.toFixed(2)}
            </div>
          </div>
          <div className="border-l border-slate-800 pl-3">
            <span className="text-[11px] font-medium uppercase tracking-wider text-indigo-300">
              理論株価 (Base DCF)
            </span>
            <div className="mt-0.5 font-mono text-xl font-bold text-emerald-400">
              ${stock.base_price.toFixed(2)}
            </div>
          </div>
        </div>

        {/* 3-Bar Scenario Visualization (Bull / Base / Bear) */}
        <div className="mt-4 space-y-2">
          <div className="flex items-center justify-between text-[11px] text-slate-400">
            <span>DCF シナリオレンジ</span>
            <span className="font-mono text-slate-400">
              WACC {(stock.wacc * 100).toFixed(1)}% | 成長率{" "}
              {(stock.growth_rate_base * 100).toFixed(1)}%
            </span>
          </div>

          {/* Bull Bar */}
          <div className="space-y-1">
            <div className="flex justify-between font-mono text-xs">
              <span className="text-indigo-300">Bull (強気)</span>
              <span className="font-semibold text-indigo-200">
                ${stock.bull_price.toFixed(2)}
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-slate-800">
              <div
                className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-indigo-400"
                style={{ width: `${bullWidth}%` }}
              />
            </div>
          </div>

          {/* Base Bar */}
          <div className="space-y-1">
            <div className="flex justify-between font-mono text-xs">
              <span className="text-emerald-300">Base (基本)</span>
              <span className="font-semibold text-emerald-200">
                ${stock.base_price.toFixed(2)}
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-slate-800">
              <div
                className="h-full rounded-full bg-gradient-to-r from-emerald-500 to-emerald-400"
                style={{ width: `${baseWidth}%` }}
              />
            </div>
          </div>

          {/* Bear Bar */}
          <div className="space-y-1">
            <div className="flex justify-between font-mono text-xs">
              <span className="text-slate-400">Bear (弱気)</span>
              <span className="font-semibold text-slate-300">
                ${stock.bear_price.toFixed(2)}
              </span>
            </div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-slate-800">
              <div
                className="h-full rounded-full bg-slate-500"
                style={{ width: `${bearWidth}%` }}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Bottom: LLM Reasoning 100-char Preview */}
      <div className="mt-4 border-t border-slate-800/80 pt-3">
        <div className="mb-1 flex items-center justify-between text-[11px] font-medium text-indigo-300">
          <span className="inline-flex items-center gap-1">
            <Sparkles className="h-3 w-3 text-indigo-400" />
            argon 算出根拠プレビュー
          </span>
          <span className="inline-flex items-center text-slate-400 group-hover:text-emerald-400">
            詳細・DCF再計算
            <ChevronRight className="h-3.5 w-3.5 transition-transform group-hover:translate-x-0.5" />
          </span>
        </div>
        <p className="text-xs leading-relaxed text-slate-300">
          {reasoningPreview}
        </p>
      </div>
    </div>
  );
}
