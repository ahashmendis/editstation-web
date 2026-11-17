import { describe, expect, it } from "vitest";

import {
  homePathFor,
  isClientPath,
  isPublicClientPath,
  toClientStatus,
  type RoutingAccess,
} from "./home-path";

const base: RoutingAccess = {
  isAdminAccount: false,
  aal: "aal1",
  clientStatus: null,
  editorAccessStatus: "none",
};

describe("homePathFor", () => {
  it("sends an active client to /client, never /apply, although editor status is none", () => {
    expect(homePathFor({ ...base, clientStatus: "active" })).toBe("/client");
  });

  it("sends a client whose access was removed to the access-ended page", () => {
    expect(homePathFor({ ...base, clientStatus: "revoked" })).toBe("/client/access-ended");
  });

  it("keeps admins on the MFA screen until verified, then the admin area", () => {
    expect(homePathFor({ ...base, isAdminAccount: true })).toBe("/mfa");
    expect(homePathFor({ ...base, isAdminAccount: true, aal: "aal2" })).toBe("/admin");
  });

  it("sends active editors to /editor and everyone else to /apply", () => {
    expect(homePathFor({ ...base, editorAccessStatus: "active" })).toBe("/editor");
    expect(homePathFor(base)).toBe("/apply");
    expect(homePathFor({ ...base, editorAccessStatus: "suspended" })).toBe("/apply");
  });

  it("an active editor who once was a client stays an editor", () => {
    expect(homePathFor({ ...base, editorAccessStatus: "active", clientStatus: "revoked" })).toBe(
      "/editor",
    );
  });
});

describe("toClientStatus", () => {
  it("accepts only the two known values", () => {
    expect(toClientStatus("active")).toBe("active");
    expect(toClientStatus("revoked")).toBe("revoked");
    expect(toClientStatus(null)).toBeNull();
    expect(toClientStatus("admin")).toBeNull();
    expect(toClientStatus(1)).toBeNull();
  });
});

describe("client paths", () => {
  it("only the code sign-in page is public under /client", () => {
    expect(isPublicClientPath("/client/sign-in")).toBe(true);
    expect(isPublicClientPath("/client")).toBe(false);
    expect(isPublicClientPath("/client/access-ended")).toBe(false);
  });

  it("matches /client and its children only", () => {
    expect(isClientPath("/client")).toBe(true);
    expect(isClientPath("/client/projects/1")).toBe(true);
    expect(isClientPath("/clients")).toBe(false);
    expect(isClientPath("/admin/clients")).toBe(false);
  });
});
