/**
 * x-gateway - Main entry point
 *
 * x api client
 */

import { greet } from "./lib";

function main(): void {
  const message = greet("World");
  console.log(message);
}

main();
