-- =====================================================================
-- 08_exemplo_venda.sql - Passo a passo de uma venda com saida FIFO
-- Roda numa transacao com ROLLBACK: mostra o resultado sem gravar nada.
-- =====================================================================
BEGIN;

-- 1. Antes: fila de saida do cimento
SELECT Ordem_saida, Codigo_lote, Data_validade, Codigo_endereco, Quantidade
  FROM VW_FILA_FIFO WHERE Sku = 'CIM-CPII-50' ORDER BY Ordem_saida;

-- 2. Registra a venda de 50 sacos para a cliente Juliana Santos
INSERT INTO VENDA (Data_venda, Id_cliente, Id_funcionario)
VALUES (CURRENT_DATE, 4, 3)
RETURNING Id_venda AS venda \gset

INSERT INTO ITEM_VENDA (Id_venda, Id_produto, Quantidade_item, Preco_unitario)
VALUES (:venda, 1, 50, 38.90)
RETURNING Id_item_venda AS item \gset

-- 3. Separa pelo FIFO: o sistema escolhe lotes e enderecos
SELECT * FROM fn_registrar_saida_fifo(:item, 4);

-- 4. Depois: o saldo ja foi baixado pelo gatilho
SELECT Ordem_saida, Codigo_lote, Data_validade, Codigo_endereco, Quantidade
  FROM VW_FILA_FIFO WHERE Sku = 'CIM-CPII-50' ORDER BY Ordem_saida;

ROLLBACK;
