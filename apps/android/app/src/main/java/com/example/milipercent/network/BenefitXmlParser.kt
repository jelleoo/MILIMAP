package com.example.milipercent.network

import com.example.milipercent.model.Benefit
import com.example.milipercent.model.BenefitPage
import java.io.IOException
import java.io.InputStream
import javax.xml.parsers.ParserConfigurationException
import javax.xml.parsers.SAXParserFactory
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler

class BenefitXmlParser {
    fun parse(inputStream: InputStream): BenefitPage {
        val handler = BenefitXmlHandler()

        try {
            createParserFactory().newSAXParser().parse(inputStream, handler)
        } catch (exception: ParserConfigurationException) {
            throw BenefitParsingException("XML parser 보안 설정을 적용하지 못했습니다.", exception)
        } catch (exception: SAXException) {
            throw BenefitParsingException("XML 응답을 해석하지 못했습니다.", exception)
        } catch (exception: RuntimeException) {
            throw BenefitParsingException("XML 응답 구조가 예상과 다릅니다.", exception)
        }

        val resultCode = handler.resultCode ?: handler.returnReasonCode
            ?: throw BenefitParsingException("응답에 resultCode가 없습니다.")
        val resultMessage = handler.resultMessage ?: handler.returnAuthMessage

        if (resultCode != SUCCESS_RESULT_CODE) {
            val message = resultMessage ?: "원인 정보 없음"
            throw BenefitApiException("공공 API 오류 ($resultCode): $message")
        }

        val pageNo = handler.pageNo?.takeIf { it > 0 }
            ?: throw BenefitParsingException("응답의 pageNo가 올바르지 않습니다.")
        val numOfRows = handler.numOfRows?.takeIf { it > 0 }
            ?: throw BenefitParsingException("응답의 numOfRows가 올바르지 않습니다.")
        val totalCount = handler.totalCount?.takeIf { it >= 0 }
            ?: throw BenefitParsingException("응답의 totalCount가 올바르지 않습니다.")

        return BenefitPage(
            benefits = handler.benefits,
            pageNo = pageNo,
            numOfRows = numOfRows,
            totalCount = totalCount,
        )
    }

    private fun createParserFactory(): SAXParserFactory =
        SAXParserFactory.newInstance().apply {
            isNamespaceAware = false

            setFeature(DISALLOW_DOCTYPE, true)
            setFeature(EXTERNAL_GENERAL_ENTITIES, false)
            setFeature(EXTERNAL_PARAMETER_ENTITIES, false)
        }

    private class BenefitXmlHandler : DefaultHandler() {
        val benefits = mutableListOf<Benefit>()
        var resultCode: String? = null
        var resultMessage: String? = null
        var returnReasonCode: String? = null
        var returnAuthMessage: String? = null
        var pageNo: Int? = null
        var numOfRows: Int? = null
        var totalCount: Int? = null

        private var currentItem: MutableBenefit? = null
        private val text = StringBuilder()

        override fun startElement(
            uri: String?,
            localName: String?,
            qName: String?,
            attributes: Attributes?,
        ) {
            text.setLength(0)
            if (tagName(localName, qName) == "item") {
                currentItem = MutableBenefit()
            }
        }

        override fun characters(characters: CharArray, start: Int, length: Int) {
            text.append(characters, start, length)
        }

        override fun resolveEntity(publicId: String?, systemId: String?): InputSource {
            throw SAXException("외부 XML 엔터티는 허용되지 않습니다.")
        }

        override fun endElement(uri: String?, localName: String?, qName: String?) {
            val tag = tagName(localName, qName)
            val value = text.toString().trim().takeIf(String::isNotEmpty)

            when (tag) {
                "resultCode" -> resultCode = value
                "resultMsg" -> resultMessage = value
                "returnReasonCode" -> returnReasonCode = value
                "returnAuthMsg" -> returnAuthMessage = value
                "pageNo" -> pageNo = value?.toIntOrNull()
                "numOfRows" -> numOfRows = value?.toIntOrNull()
                "totalCount" -> totalCount = value?.toIntOrNull()
                "rnum" -> currentItem?.id = value?.toIntOrNull()
                "udaeGgm" -> currentItem?.name = value
                "juso" -> currentItem?.address = value
                "udgigwanTelno" -> currentItem?.phone = value
                "gtcdNm" -> currentItem?.benefitType = value
                "item" -> finishCurrentItem()
            }

            text.setLength(0)
        }

        private fun finishCurrentItem() {
            val item = currentItem ?: return
            val id = item.id ?: throw SAXException("item의 rnum이 없거나 숫자가 아닙니다.")

            benefits += Benefit(
                id = id,
                name = item.name.orEmpty(),
                address = item.address,
                phone = item.phone,
                benefitType = item.benefitType,
            )
            currentItem = null
        }

        private fun tagName(localName: String?, qName: String?): String =
            qName?.takeIf(String::isNotEmpty) ?: localName.orEmpty()
    }

    private class MutableBenefit(
        var id: Int? = null,
        var name: String? = null,
        var address: String? = null,
        var phone: String? = null,
        var benefitType: String? = null,
    )

    private companion object {
        const val SUCCESS_RESULT_CODE = "00"
        const val DISALLOW_DOCTYPE = "http://apache.org/xml/features/disallow-doctype-decl"
        const val EXTERNAL_GENERAL_ENTITIES =
            "http://xml.org/sax/features/external-general-entities"
        const val EXTERNAL_PARAMETER_ENTITIES =
            "http://xml.org/sax/features/external-parameter-entities"
    }
}

class BenefitApiException(message: String) : IOException(message)

class BenefitParsingException(message: String, cause: Throwable? = null) :
    IOException(message, cause)
