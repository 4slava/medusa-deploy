import { PRICE_CURRENCIES, toProductPricing } from "../../search/helpers/pricing";

const variant = (calculated: number | null, original?: number | null) => ({
  calculated_price: { calculated_amount: calculated, original_amount: original },
});

describe("toProductPricing", () => {
  it("takes min and original from the cheapest variant and max from the dearest", () => {
    expect(
      toProductPricing({
        eur: [variant(30, 40), variant(10, 15), variant(20, 20)],
      }),
    ).toEqual({
      min_price_eur: 10,
      max_price_eur: 30,
      original_price_eur: 15,
      on_sale_eur: true,
    });
  });

  it("writes on_sale false when the cheapest variant is not discounted", () => {
    expect(toProductPricing({ usd: [variant(12, 12), variant(20, 30)] })).toEqual({
      min_price_usd: 12,
      max_price_usd: 20,
      original_price_usd: 12,
      on_sale_usd: false,
    });
  });

  it("uses the calculated amount when the original is missing", () => {
    expect(toProductPricing({ eur: [variant(25, null)] })).toEqual({
      min_price_eur: 25,
      max_price_eur: 25,
      original_price_eur: 25,
      on_sale_eur: false,
    });
  });

  it("skips variants without a calculated price", () => {
    expect(
      toProductPricing({
        eur: [null, { calculated_price: null }, variant(null, 50), variant(5, 5)],
      }),
    ).toEqual({
      min_price_eur: 5,
      max_price_eur: 5,
      original_price_eur: 5,
      on_sale_eur: false,
    });
  });

  it("writes nothing for a currency without prices", () => {
    expect(toProductPricing({ eur: [variant(null)], usd: null })).toEqual({});
    expect(toProductPricing(undefined)).toEqual({});
  });

  it("covers every configured currency", () => {
    const rows = Object.fromEntries(PRICE_CURRENCIES.map((c) => [c, [variant(1)]]));
    const pricing = toProductPricing(rows);

    for (const currency of PRICE_CURRENCIES) {
      expect(pricing).toHaveProperty(`min_price_${currency}`, 1);
    }
  });
});
