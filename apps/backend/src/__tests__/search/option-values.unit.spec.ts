import { toOptionValues } from "../../search/helpers/option-values";

describe("toOptionValues", () => {
  it("flattens options into title:value pairs", () => {
    expect(
      toOptionValues([
        { title: "Size", values: [{ value: "S" }, { value: "M" }] },
        { title: "Color", values: [{ value: "Red" }] },
      ]),
    ).toEqual(["Size:S", "Size:M", "Color:Red"]);
  });

  it("trims titles and values", () => {
    expect(
      toOptionValues([{ title: " Size ", values: [{ value: " L " }] }]),
    ).toEqual(["Size:L"]);
  });

  it("skips options without a title and empty values", () => {
    expect(
      toOptionValues([
        { title: "", values: [{ value: "S" }] },
        { title: null, values: [{ value: "M" }] },
        null,
        { title: "Size", values: [null, { value: "" }, { value: null }, { value: "XL" }] },
      ]),
    ).toEqual(["Size:XL"]);
  });

  it("removes duplicates", () => {
    expect(
      toOptionValues([
        { title: "Size", values: [{ value: "S" }, { value: "S" }] },
      ]),
    ).toEqual(["Size:S"]);
  });

  it("returns an empty list for missing options", () => {
    expect(toOptionValues(null)).toEqual([]);
    expect(toOptionValues(undefined)).toEqual([]);
    expect(toOptionValues([])).toEqual([]);
  });
});
