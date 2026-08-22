package com.example.milipercent.network

import java.io.ByteArrayInputStream
import kotlin.text.Charsets.UTF_8
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class BenefitXmlParserTest {
    private val parser = BenefitXmlParser()

    @Test
    fun `정상 XML을 Benefit 목록으로 변환한다`() {
        val page = parse(
            """
            <response>
                <header>
                    <resultCode>00</resultCode>
                    <resultMsg>NORMAL SERVICE.</resultMsg>
                </header>
                <body>
                    <items>
                        <item>
                            <gtcdNm>할인</gtcdNm>
                            <juso>경기도 화성시</juso>
                            <rnum>1</rnum>
                            <udaeGgm>홍안경</udaeGgm>
                            <udgigwanTelno>031-372-1001</udgigwanTelno>
                        </item>
                        <item>
                            <gtcdNm></gtcdNm>
                            <rnum>2</rnum>
                            <udaeGgm>주소 없는 가게</udaeGgm>
                        </item>
                    </items>
                    <numOfRows>100</numOfRows>
                    <pageNo>1</pageNo>
                    <totalCount>202</totalCount>
                </body>
            </response>
            """.trimIndent(),
        )

        val benefits = page.benefits
        assertEquals(1, page.pageNo)
        assertEquals(100, page.numOfRows)
        assertEquals(202, page.totalCount)
        assertEquals(2, benefits.size)
        assertEquals("홍안경", benefits[0].name)
        assertEquals("경기도 화성시", benefits[0].address)
        assertEquals("031-372-1001", benefits[0].phone)
        assertEquals("할인", benefits[0].benefitType)
        assertNull(benefits[1].address)
        assertNull(benefits[1].phone)
        assertNull(benefits[1].benefitType)
    }

    @Test
    fun `items가 비어 있으면 빈 목록을 반환한다`() {
        val page = parse(
            """
            <response>
                <header><resultCode>00</resultCode></header>
                <body>
                    <items></items>
                    <numOfRows>100</numOfRows>
                    <pageNo>1</pageNo>
                    <totalCount>0</totalCount>
                </body>
            </response>
            """.trimIndent(),
        )

        assertTrue(page.benefits.isEmpty())
    }

    @Test
    fun `업체명이 누락되어도 빈 값으로 유지한다`() {
        val page = parse(
            """
            <response>
                <header><resultCode>00</resultCode></header>
                <body>
                    <items><item><rnum>1</rnum></item></items>
                    <numOfRows>100</numOfRows>
                    <pageNo>1</pageNo>
                    <totalCount>1</totalCount>
                </body>
            </response>
            """.trimIndent(),
        )

        assertEquals("", page.benefits.single().name)
    }

    @Test
    fun `resultCode가 00이 아니면 API 오류로 처리한다`() {
        val exception = assertThrows(BenefitApiException::class.java) {
            parse(
                """
                <response>
                    <header>
                        <resultCode>30</resultCode>
                        <resultMsg>SERVICE KEY IS NOT REGISTERED ERROR.</resultMsg>
                    </header>
                </response>
                """.trimIndent(),
            )
        }

        assertTrue(exception.message.orEmpty().contains("30"))
    }

    @Test
    fun `잘못된 XML이면 파싱 오류로 처리한다`() {
        assertThrows(BenefitParsingException::class.java) {
            parse("<response><header><resultCode>00</resultCode></header>")
        }
    }

    private fun parse(xml: String) =
        ByteArrayInputStream(xml.toByteArray(UTF_8)).use(parser::parse)
}
