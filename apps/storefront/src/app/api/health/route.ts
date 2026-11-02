import { NextResponse } from "next/server"

/**
 * Health check endpoint used by Docker and the deploy smoke test.
 * GET /api/health → { status: "ok" }
 */
export function GET() {
  return NextResponse.json({ status: "ok" })
}
