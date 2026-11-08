# Contribuir

Abra uma issue com a versão do Omarchy, o comportamento esperado e o observado.
Ao compartilhar telemetria, remova o número de série. Não são necessários dados
pessoais ou configurações completas do desktop.

Para um PR:

1. Crie uma branch e mantenha as alterações no plugin do usuário.
2. Preserve os componentes `qs.Ui` e os tokens do tema. Leia `DESIGN.md`.
3. Acrescente strings em `i18n/en.json`, `pt.json` e `pt-BR.json`.
4. Renderize dados de hardware como `Text.PlainText` e nunca os interpole em shell.
5. Para mudanças de telemetria, acrescente testes com sysfs temporário em `tests/`.
6. Execute `bash scripts/check.sh` e confira o painel em uma sessão Omarchy:
   resumo, detalhes expandidos, D, Esc, rolagem, perfis, idioma e campos ausentes.

A validação estática e os testes com fixtures não substituem a integração real
com Quickshell, UPower e a barra. Não edite `/usr/share/omarchy/` para testar.
