defmodule Watchman.News.CVMTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.NewsItem
  alias Watchman.News.CVM

  @valid_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <CVM>
    <documento>
      <tipo>Fato Relevante</tipo>
      <titulo>Aquisição de participação societária</titulo>
      <url>https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=100</url>
      <dataEntrega>2026-04-15T14:30:00</dataEntrega>
    </documento>
    <documento>
      <tipo>DFP</tipo>
      <titulo>Demonstrações Financeiras Padronizadas 2025</titulo>
      <url>https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=200</url>
      <dataEntrega>2026-03-20T10:00:00</dataEntrega>
    </documento>
    <documento>
      <tipo>Comunicado ao Mercado</tipo>
      <titulo>Pagamento de dividendos referente ao 4T25</titulo>
      <url>https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=300</url>
      <dataEntrega>2026-02-10T09:00:00</dataEntrega>
    </documento>
  </CVM>
  """

  @empty_xml "<CVM/>"

  @malformed_xml "this is not xml <<<"

  describe "parse_response/2 with valid XML" do
    test "returns three NewsItems with correct source and categories" do
      assert {:ok, items} = CVM.parse_response(@valid_xml, "PETR4")
      assert length(items) == 3
      assert Enum.all?(items, fn item -> item.source == "cvm" end)

      [material_fact_item, financial_item, dividend_item] = items

      assert material_fact_item.category == "material_fact"
      assert material_fact_item.title == "Aquisição de participação societária"
      assert material_fact_item.url == "https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=100"
      assert material_fact_item.published_at == ~U[2026-04-15 14:30:00Z]

      assert financial_item.category == "financial_result"
      assert financial_item.title == "Demonstrações Financeiras Padronizadas 2025"
      assert financial_item.published_at == ~U[2026-03-20 10:00:00Z]

      assert dividend_item.category == "dividend"
      assert String.contains?(dividend_item.title, "dividendos")
      assert dividend_item.published_at == ~U[2026-02-10 09:00:00Z]
    end

    test "each item is a NewsItem struct" do
      assert {:ok, items} = CVM.parse_response(@valid_xml, "PETR4")
      assert Enum.all?(items, fn item -> %NewsItem{} = item end)
    end
  end

  describe "parse_response/2 edge cases" do
    test "returns {:ok, []} for empty <CVM/> document" do
      assert {:ok, []} = CVM.parse_response(@empty_xml, "PETR4")
    end

    test "returns {:error, _} for malformed XML" do
      assert {:error, _} = CVM.parse_response(@malformed_xml, "PETR4")
    end
  end

  describe "category mapping via parse_response/2" do
    test "Fato Relevante maps to material_fact" do
      xml = build_xml("Fato Relevante", "Título qualquer")
      assert {:ok, [%NewsItem{category: "material_fact"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "ITR maps to financial_result" do
      xml = build_xml("ITR", "Informações Trimestrais 1T26")
      assert {:ok, [%NewsItem{category: "financial_result"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "DFP maps to financial_result" do
      xml = build_xml("DFP", "Demonstrações Financeiras Padronizadas")
      assert {:ok, [%NewsItem{category: "financial_result"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "tipo containing Demonstrações Financeiras maps to financial_result" do
      xml = build_xml("Demonstrações Financeiras Especiais", "Relatório anual")
      assert {:ok, [%NewsItem{category: "financial_result"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "Comunicado ao Mercado with dividendo in title maps to dividend" do
      xml = build_xml("Comunicado ao Mercado", "Pagamento de dividendo interim")
      assert {:ok, [%NewsItem{category: "dividend"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "Comunicado ao Mercado with JCP in title maps to dividend" do
      xml = build_xml("Comunicado ao Mercado", "Distribuição de JCP referente ao 2T26")
      assert {:ok, [%NewsItem{category: "dividend"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "Comunicado ao Mercado without dividendo or JCP maps to other" do
      xml = build_xml("Comunicado ao Mercado", "Alteração na composição da diretoria")
      assert {:ok, [%NewsItem{category: "other"}]} = CVM.parse_response(xml, "VALE3")
    end

    test "unknown tipo maps to other" do
      xml = build_xml("Aviso aos Acionistas", "Assembleia Geral Ordinária")
      assert {:ok, [%NewsItem{category: "other"}]} = CVM.parse_response(xml, "VALE3")
    end
  end

  defp build_xml(tipo, titulo) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <CVM>
      <documento>
        <tipo>#{tipo}</tipo>
        <titulo>#{titulo}</titulo>
        <url>https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=1</url>
        <dataEntrega>2026-05-01T08:00:00</dataEntrega>
      </documento>
    </CVM>
    """
  end
end
