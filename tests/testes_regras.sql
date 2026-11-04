-- =====================================================================
-- testes_regras.sql - Testes automaticos das regras de negocio
--
-- Pre-requisito: banco criado com db/01..04 (dados de exemplo).
-- Tudo roda dentro de uma transacao que termina em ROLLBACK:
-- os testes nao alteram o banco.
--
-- Uso: psql -v ON_ERROR_STOP=1 -d bd_deposito -f tests/testes_regras.sql
-- Cada teste imprime "ok - ..."; o primeiro que falhar interrompe com erro.
-- =====================================================================

SET search_path TO estoque, public;
SET client_min_messages TO notice;
\o /dev/null

BEGIN;

-- ---------- Funcoes auxiliares (temporarias, somem ao fim da sessao) ----------

-- Executa os comandos e exige que algum deles falhe com uma mensagem contendo p_trecho
CREATE FUNCTION pg_temp.espera_erro(p_nome TEXT, p_trecho TEXT, p_cmds TEXT[])
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    c TEXT;
BEGIN
    BEGIN
        FOREACH c IN ARRAY p_cmds LOOP
            EXECUTE c;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
        IF position(lower(p_trecho) IN lower(SQLERRM)) > 0 THEN
            RAISE NOTICE 'ok - %', p_nome;
            RETURN;
        END IF;
        RAISE EXCEPTION 'FALHOU - %: erro inesperado: %', p_nome, SQLERRM;
    END;
    RAISE EXCEPTION 'FALHOU - %: era esperado erro contendo "%"', p_nome, p_trecho;
END $$;

CREATE FUNCTION pg_temp.confere(p_nome TEXT, p_obtido TEXT, p_esperado TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF p_obtido IS DISTINCT FROM p_esperado THEN
        RAISE EXCEPTION 'FALHOU - %: esperado [%], obtido [%]', p_nome, p_esperado, p_obtido;
    END IF;
    RAISE NOTICE 'ok - %', p_nome;
END $$;

-- ---------- 1. Carga de exemplo e consistencia do saldo ----------
SELECT pg_temp.confere('saldo de cada lote/endereco = entradas - saidas',
    (SELECT COUNT(*)::TEXT FROM (
        SELECT Id_lote, Id_endereco,
               SUM(CASE Tipo_mov WHEN 'E' THEN Quantidade_mov ELSE -Quantidade_mov END) AS Calc
          FROM MOVIMENTACAO GROUP BY Id_lote, Id_endereco
    ) m
    FULL JOIN ESTOQUE_ENDERECO ee USING (Id_lote, Id_endereco)
    WHERE COALESCE(m.Calc, 0) IS DISTINCT FROM COALESCE(ee.Quantidade, 0)),
    '0');

SELECT pg_temp.confere('toda movimentacao esta na subclasse do seu tipo',
    (SELECT COUNT(*)::TEXT FROM MOVIMENTACAO m
      WHERE (m.Tipo_mov = 'E') <> EXISTS (SELECT 1 FROM ENTRADA_ESTOQUE e WHERE e.Id_movimentacao = m.Id_movimentacao)
         OR (m.Tipo_mov = 'S') <> EXISTS (SELECT 1 FROM SAIDA_ESTOQUE s   WHERE s.Id_movimentacao = m.Id_movimentacao)),
    '0');

SELECT pg_temp.confere('saida de 3 dias atras usou o lote que vencia primeiro (CIM-A1)',
    (SELECT string_agg(Codigo_lote, ',') FROM VW_EXTRATO_MOVIMENTACAO
      WHERE Tipo = 'SAIDA' AND Sku = 'CIM-CPII-50' AND Id_venda = 1),
    'CIM-A1');

SELECT pg_temp.confere('saida de hoje pulou o lote vencido CIM-A1 e usou CIM-A2',
    (SELECT string_agg(Codigo_lote, ',') FROM VW_EXTRATO_MOVIMENTACAO
      WHERE Tipo = 'SAIDA' AND Sku = 'CIM-CPII-50' AND Id_venda = 3),
    'CIM-A2');

SELECT pg_temp.confere('dentro do lote, a saida sai do picking antes da reserva',
    (SELECT Codigo_endereco FROM VW_EXTRATO_MOVIMENTACAO
      WHERE Tipo = 'SAIDA' AND Sku = 'TIN-ACR-18'),
    'B-01-1');

SELECT pg_temp.confere('relatorio aponta 8 sacos de cimento vencidos',
    (SELECT Saldo_vencido::TEXT FROM VW_SALDO_PRODUTO WHERE Sku = 'CIM-CPII-50'),
    '8');

-- ---------- 2. Sugestao de endereco ----------
SELECT pg_temp.confere('sugestao consolida o produto em endereco de reserva que ja o guarda',
    (SELECT Codigo_endereco FROM ENDERECO WHERE Id_endereco = fn_sugerir_endereco(3, 5)),
    'P-01-0');

SELECT pg_temp.confere('sem endereco que comporte a quantidade, a sugestao e nula',
    fn_sugerir_endereco(3, 10000)::TEXT, NULL);

-- ---------- 3. Saida FIFO de uma nova venda ----------
-- As chaves IDENTITY foram ajustadas pela carga: INSERT sem Id funciona
INSERT INTO VENDA (Data_venda, Id_cliente, Id_funcionario) VALUES (CURRENT_DATE, 4, 3);
INSERT INTO ITEM_VENDA (Id_venda, Id_produto, Quantidade_item, Preco_unitario)
VALUES (currval(pg_get_serial_sequence('estoque.venda', 'id_venda')), 1, 10, 38.90);

CREATE TEMP TABLE t_saida AS
SELECT * FROM fn_registrar_saida_fifo(
    currval(pg_get_serial_sequence('estoque.item_venda', 'id_item_venda'))::INT, 4);

SELECT pg_temp.confere('venda de 10 sacos: 5 do endereco que esvazia, 5 do outro, mesmo lote',
    (SELECT string_agg(Codigo_lote || '@' || Codigo_endereco || '=' || Quantidade, ' '
                       ORDER BY Id_movimentacao) FROM t_saida),
    'CIM-A2@A-01-2=5 CIM-A2@A-01-1=5');

SELECT pg_temp.confere('endereco esvaziado sai de ESTOQUE_ENDERECO',
    (SELECT COUNT(*)::TEXT FROM ESTOQUE_ENDERECO ee JOIN ENDERECO e USING (Id_endereco)
      WHERE e.Codigo_endereco = 'A-01-2'),
    '0');

SELECT pg_temp.confere('chamar de novo para o mesmo item nao gera saida duplicada',
    (SELECT COUNT(*)::TEXT FROM fn_registrar_saida_fifo(
        currval(pg_get_serial_sequence('estoque.item_venda', 'id_item_venda'))::INT, 4)),
    '0');

-- ---------- 4. Regras que devem bloquear a operacao ----------
INSERT INTO ITEM_VENDA (Id_venda, Id_produto, Quantidade_item, Preco_unitario)
VALUES (currval(pg_get_serial_sequence('estoque.venda', 'id_venda')), 4, 999, 289.90);

SELECT pg_temp.espera_erro('estoque insuficiente bloqueia a saida inteira', 'insuficiente',
    ARRAY[format('SELECT fn_registrar_saida_fifo(%s, 4)',
          currval(pg_get_serial_sequence('estoque.item_venda', 'id_item_venda')))]);

SELECT pg_temp.espera_erro('entrada acima da capacidade do endereco', 'sem espaco',
    ARRAY['SELECT fn_registrar_entrada(9, 30, 2, 6)']);          -- P-02-0: 92 + 30 > 120

SELECT pg_temp.espera_erro('zona que nao aceita a categoria (ACEITA)', 'nao aceita',
    ARRAY['SELECT fn_registrar_entrada(6, 1, 2, 11)']);          -- tinta no mezanino

SELECT pg_temp.espera_erro('entrada em endereco inativo', 'inativo',
    ARRAY['SELECT fn_registrar_entrada(12, 1, 2, 13)']);         -- M-02-1 em manutencao

SELECT pg_temp.espera_erro('entrada de lote vencido', 'vencido',
    ARRAY['SELECT fn_registrar_entrada(1, 1, 2, 14)']);          -- CIM-A1

SELECT pg_temp.espera_erro('saida com lote de outro produto', 'produto',
    ARRAY['INSERT INTO MOVIMENTACAO (Id_movimentacao, Tipo_mov, Quantidade_mov, Id_lote, Id_endereco, Id_funcionario)
           VALUES (9001, ''S'', 1, 6, 7, 4)',                    -- tinta TA-2310
          'INSERT INTO SAIDA_ESTOQUE VALUES (9001, 1)']);        -- item 1 = cimento

SELECT pg_temp.espera_erro('saida maior que a quantidade vendida', 'ja atendido',
    ARRAY['INSERT INTO MOVIMENTACAO (Id_movimentacao, Tipo_mov, Quantidade_mov, Id_lote, Id_endereco, Id_funcionario)
           VALUES (9002, ''S'', 1, 2, 1, 4)',
          'INSERT INTO SAIDA_ESTOQUE VALUES (9002, 1)']);        -- item 1 ja recebeu 12 de 12

-- ---------- 5. Especializacao total e disjunta (opcao 8A + gatilhos) ----------
SELECT pg_temp.espera_erro('MOVIMENTACAO sem subclasse (especializacao total)', 'sem linha',
    ARRAY['INSERT INTO MOVIMENTACAO (Id_movimentacao, Tipo_mov, Quantidade_mov, Id_lote, Id_endereco, Id_funcionario)
           VALUES (9003, ''E'', 1, 9, 6, 2)',
          'SET CONSTRAINTS ALL IMMEDIATE']);                     -- antecipa a checagem do COMMIT

SELECT pg_temp.espera_erro('saida registrada como entrada (disjuncao)', 'nao pode estar',
    ARRAY[format('INSERT INTO ENTRADA_ESTOQUE VALUES (%s, NULL)',
          (SELECT MIN(Id_movimentacao) FROM SAIDA_ESTOQUE))]);

SELECT pg_temp.espera_erro('ENDERECO sem subclasse (especializacao total)', 'sem linha',
    ARRAY['INSERT INTO ENDERECO (Id_endereco, Id_zona, Codigo_endereco, Corredor, Modulo, Nivel, Capacidade_max, Tipo_endereco)
           VALUES (9001, 1, ''A-09-1'', ''A'', 9, 1, 40, ''PP'')',
          'SET CONSTRAINTS ALL IMMEDIATE']);

SELECT pg_temp.espera_erro('prateleira cadastrada como piso (disjuncao)', 'nao pode estar',
    ARRAY['INSERT INTO ENDERECO_PISO VALUES (7, 1.00, 5)']);     -- B-01-1 e PR

-- ---------- 6. Historico imutavel ----------
SELECT pg_temp.espera_erro('UPDATE em movimentacao', 'imutavel',
    ARRAY['UPDATE MOVIMENTACAO SET Quantidade_mov = 1 WHERE Id_movimentacao = 1']);

SELECT pg_temp.espera_erro('DELETE em movimentacao', 'imutavel',
    ARRAY['DELETE FROM MOVIMENTACAO WHERE Id_movimentacao = 1']);

-- ---------- 7. Restricoes do proprio esquema (CHECK, UNIQUE, FK) ----------
SELECT pg_temp.espera_erro('produto perecivel sem prazo de validade', 'ck_produto_validade',
    ARRAY['INSERT INTO PRODUTO (Sku, Descricao, Unidade, Perecivel, Id_categoria)
           VALUES (''X-1'', ''Teste'', ''PC'', ''S'', 1)']);

SELECT pg_temp.espera_erro('SKU repetido', 'uq_produto_sku',
    ARRAY['INSERT INTO PRODUTO (Sku, Descricao, Unidade, Perecivel, Id_categoria)
           VALUES (''CIM-CPII-50'', ''Duplicado'', ''SC'', ''N'', 1)']);

SELECT pg_temp.espera_erro('lote de produto inexistente', 'fk_lote_produto',
    ARRAY['INSERT INTO LOTE (Id_produto, Id_recebimento, Codigo_lote, Quantidade_recebida)
           VALUES (999, 1, ''Z'', 1)']);

DO $$ BEGIN RAISE NOTICE 'Todos os testes passaram.'; END $$;

ROLLBACK;
