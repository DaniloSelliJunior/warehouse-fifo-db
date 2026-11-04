-- =====================================================================
-- 05_aderencia_sugestao.sql - O operador segue o endereco sugerido?
-- Usa o relacionamento SUGERE (participacao parcial: sugestao pode ser nula).
-- =====================================================================

SELECT COUNT(*)                                                     AS Entradas,
       COUNT(*) FILTER (WHERE en.Id_endereco_sugerido = m.Id_endereco) AS Seguiu_sugestao,
       COUNT(*) FILTER (WHERE en.Id_endereco_sugerido <> m.Id_endereco) AS Outro_endereco,
       COUNT(*) FILTER (WHERE en.Id_endereco_sugerido IS NULL)          AS Sem_sugestao,
       ROUND(100.0 * COUNT(*) FILTER (WHERE en.Id_endereco_sugerido = m.Id_endereco)
             / NULLIF(COUNT(*), 0), 1)                              AS Aderencia_pct
  FROM MOVIMENTACAO m
  JOIN ENTRADA_ESTOQUE en ON en.Id_movimentacao = m.Id_movimentacao;

-- Entradas em que o operador escolheu outro endereco
SELECT Data_hora, Sku, Codigo_lote, Endereco_sugerido, Codigo_endereco AS Endereco_usado,
       Quantidade, Funcionario
  FROM VW_EXTRATO_MOVIMENTACAO
 WHERE Tipo = 'ENTRADA' AND Endereco_sugerido IS DISTINCT FROM Codigo_endereco
 ORDER BY Data_hora;
