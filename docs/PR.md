## Alteração

Adiciona um plugin instalável para o Omarchy Shell que estende `omarchy.power`
com fabricante, modelo, ciclos, capacidades, saúde, desgaste e detalhes técnicos.
O resumo usa métricas e barras comparáveis; informações adicionais ficam em uma
seção recolhível. Mantém os perfis de energia, porcentagem e tema do Omarchy.

Inclui pacote compatível com `omarchy plugin add`, instruções de instalação,
atualização, remoção e migração, licença MIT com créditos ao Omarchy, prévia,
catálogos em português/inglês, testes e CI. Nenhuma configuração pessoal do
usuário é distribuída.

## Validação

- `bash scripts/check.sh`: testes Python, manifesto, catálogos, validador nativo
  e sintaxe QML executados localmente.
- Prévias Qt conferidas em largura normal e estreita com detalhes expandidos.
- Omarchy 4.5.0-3 reconheceu a cópia local e recarregou o plugin.
- Instalação a partir do GitHub e CI remota pendentes de publicação. A interação
  completa com o desktop não pôde ser automatizada devido às restrições IPC.
