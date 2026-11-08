# Publicar com gh

O repositório tem `main` como base inicial e `feat/battery-details` com a entrega.
Para criar `eusener/omarchy-battery`, enviar as duas branches e abrir o PR:

```bash
gh auth status
# Caso não esteja autenticado:
gh auth login --hostname github.com
bash scripts/publish-gh.sh --public
```

Use `--private` se preferir um repositório privado. Nesse caso, as outras
instalações precisarão de acesso ao repositório e autenticação Git apropriada.
O script não altera a visibilidade de um repositório já existente, não usa force
push e reutiliza um PR aberto para a mesma branch.

O pacote está na branch do PR. Depois de revisar e mesclar o PR, a instalação
padrão documentada no README usará a branch `main` com o plugin completo.
Enquanto o PR estiver aberto, confira o pacote na branch `feat/battery-details`.
