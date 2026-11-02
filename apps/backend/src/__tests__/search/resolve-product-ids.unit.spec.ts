import type { SearchTypes } from "@medusajs/framework/types";

import { resolveProductIds } from "../../search/helpers/resolve-product-ids";

function contextWith(query: { graph?: jest.Mock; search?: jest.Mock }) {
  return { container: { query } } as unknown as SearchTypes.SearchIngestionContext;
}

describe("resolveProductIds", () => {
  it("returns product ids from product events without querying", async () => {
    const graph = jest.fn();

    await expect(
      resolveProductIds(
        { name: "product.updated", data: [{ id: "prod_1" }, { id: "prod_2" }] },
        contextWith({ graph }),
      ),
    ).resolves.toEqual(["prod_1", "prod_2"]);
    expect(graph).not.toHaveBeenCalled();
  });

  it("accepts a single payload object", async () => {
    await expect(
      resolveProductIds({ name: "product.created", data: { id: "prod_1" } }, contextWith({})),
    ).resolves.toEqual(["prod_1"]);
  });

  it("returns nothing for an empty payload or an unknown entity", async () => {
    const graph = jest.fn();
    const context = contextWith({ graph });

    await expect(resolveProductIds({ name: "product.updated", data: {} }, context)).resolves.toEqual([]);
    await expect(resolveProductIds({ name: "customer.updated", data: { id: "cus_1" } }, context)).resolves.toEqual([]);
    expect(graph).not.toHaveBeenCalled();
  });

  it("maps variants to their products, including deleted variants", async () => {
    const graph = jest.fn().mockResolvedValue({ data: [{ product_id: "prod_1" }, { product_id: null }] });

    await expect(
      resolveProductIds({ name: "product-variant.deleted", data: { id: "variant_1" } }, contextWith({ graph })),
    ).resolves.toEqual(["prod_1"]);
    expect(graph).toHaveBeenCalledWith({
      entity: "product_variant",
      fields: ["product_id"],
      filters: { id: ["variant_1"] },
      withDeleted: true,
    });
  });

  it("maps option values through their option", async () => {
    const graph = jest.fn().mockResolvedValue({ data: [{ option: { product_id: "prod_3" } }, { option: null }] });

    await expect(
      resolveProductIds({ name: "product-option-value.updated", data: { id: "optval_1" } }, contextWith({ graph })),
    ).resolves.toEqual(["prod_3"]);
    expect(graph).toHaveBeenCalledWith(expect.objectContaining({ entity: "product_option_value", withDeleted: false }));
  });

  it("maps tags and categories to all linked products", async () => {
    const graph = jest.fn().mockResolvedValue({
      data: [{ products: [{ id: "prod_1" }, { id: "prod_2" }] }, { products: null }],
    });

    await expect(
      resolveProductIds({ name: "product-tag.updated", data: { id: "ptag_1" } }, contextWith({ graph })),
    ).resolves.toEqual(["prod_1", "prod_2"]);
    await expect(
      resolveProductIds({ name: "product-category.deleted", data: { id: "pcat_1" } }, contextWith({ graph })),
    ).resolves.toEqual(["prod_1", "prod_2"]);
  });

  it("pages through the index for a deleted sales channel", async () => {
    const page = (count: number, offset: number) => ({
      search_result: {
        hits: Array.from({ length: count }, (_, i) => ({ id: `prod_${offset + i}` })),
      },
    });
    const search = jest.fn().mockResolvedValueOnce(page(200, 0)).mockResolvedValueOnce(page(3, 200));

    const ids = await resolveProductIds(
      { name: "sales-channel.deleted", data: { id: "sc_1" } },
      contextWith({ search }),
    );

    expect(ids).toHaveLength(203);
    expect(search).toHaveBeenCalledTimes(2);
    expect(search).toHaveBeenLastCalledWith(
      expect.objectContaining({
        filters: { sales_channel_ids: ["sc_1"] },
        pagination: { skip: 200, take: 200 },
      }),
    );
  });
});
