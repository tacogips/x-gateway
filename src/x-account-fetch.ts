function failGraphqlOnly(): never {
  throw new Error(
    [
      "x-account-fetch is not part of the current stable x-gateway contract.",
      "Use 'x-gateway account me' for the reviewed identity path, or add a dedicated capability adapter before restoring this standalone helper.",
      "Do not reintroduce this file as a hidden transport shortcut that bypasses the documented CLI/SDK surface.",
    ].join(" "),
  );
}

failGraphqlOnly();
