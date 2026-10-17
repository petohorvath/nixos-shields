{
  programs = {
    nixfmt.enable = true;
    deadnix.enable = true;
    actionlint.enable = true;
    prettier = {
      enable = true;
      settings = {
        proseWrap = "preserve";
        printWidth = 100;
      };
    };
    shfmt.enable = true;
    shellcheck.enable = true;
  };
}
