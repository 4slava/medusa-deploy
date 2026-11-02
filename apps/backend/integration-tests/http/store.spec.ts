import { medusaIntegrationTestRunner } from "@medusajs/test-utils";
import {
  createApiKeysWorkflow,
  createProductsWorkflow,
  createSalesChannelsWorkflow,
  linkSalesChannelsToApiKeyWorkflow,
} from "@medusajs/medusa/core-flows";
import { Modules, ProductStatus } from "@medusajs/framework/utils";

jest.setTimeout(120 * 1000);

medusaIntegrationTestRunner({
  inApp: true,
  env: {},
  testSuite: ({ api, getContainer }) => {
    let headers: Record<string, string>;
    let salesChannelId: string;

    beforeEach(async () => {
      const container = getContainer();
      const {
        result: [salesChannel],
      } = await createSalesChannelsWorkflow(container).run({
        input: { salesChannelsData: [{ name: "Web" }] },
      });
      const {
        result: [key],
      } = await createApiKeysWorkflow(container).run({
        input: {
          api_keys: [{ title: "Web", type: "publishable", created_by: "" }],
        },
      });
      await linkSalesChannelsToApiKeyWorkflow(container).run({
        input: { id: key.id, add: [salesChannel.id] },
      });

      salesChannelId = salesChannel.id;
      headers = { "x-publishable-api-key": key.token };
    });

    const createProduct = (title: string, status: ProductStatus) =>
      createProductsWorkflow(getContainer()).run({
        input: {
          products: [
            {
              title,
              status,
              options: [{ title: "Size", values: ["M"] }],
              variants: [{ title: "M", options: { Size: "M" }, prices: [] }],
              sales_channels: [{ id: salesChannelId }],
            },
          ],
        },
      });

    const searchTitles = async () => {
      const response = await api.post(
        "/store/search",
        { entity: "product", pagination: { take: 20, skip: 0 } },
        { headers },
      );
      return response.data.results[0].hits.map(
        (hit: { document: { title: string } }) => hit.document.title,
      );
    };

    it("answers the health check", async () => {
      const response = await api.get("/health");

      expect(response.status).toEqual(200);
    });

    it("rejects store requests without a publishable key", async () => {
      const response = await api.get("/store/products").catch((e) => e.response);

      expect(response.status).toEqual(400);
    });

    it("lists published products in the key's sales channel", async () => {
      await createProduct("Published tee", ProductStatus.PUBLISHED);

      const response = await api.get("/store/products", { headers });

      expect(response.status).toEqual(200);
      expect(response.data.products.map((p: { title: string }) => p.title)).toEqual([
        "Published tee",
      ]);
    });

    it("searches published products only", async () => {
      await createProduct("Published tee", ProductStatus.PUBLISHED);
      await createProduct("Draft tee", ProductStatus.DRAFT);
      // Fills the index from the database, as the app does at startup
      await getContainer().resolve(Modules.SEARCH).reindex();

      expect(await searchTitles()).toEqual(["Published tee"]);
    });
  },
});
