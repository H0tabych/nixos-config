# Каркас: treefmt · Домен: core
# Один форматтер/линтер-набор на тип файлов (OPS-1, DEV-8).
_:
{
  perSystem = {
    treefmt.programs = {
      nixfmt.enable = true;
      statix.enable = true;
      deadnix.enable = true;
    };
  };
}
