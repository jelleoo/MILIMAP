package com.example.milipercent.network

import javax.xml.parsers.ParserConfigurationException
import javax.xml.parsers.SAXParser
import javax.xml.parsers.SAXParserFactory

private const val DISALLOW_DOCTYPE_FEATURE =
    "http://apache.org/xml/features/disallow-doctype-decl"

class RejectingSecurityFeatureSaxParserFactory : DelegatingTestSaxParserFactory() {
    override fun setFeature(name: String, value: Boolean) {
        if (name == DISALLOW_DOCTYPE_FEATURE) {
            throw ParserConfigurationException("TEST ONLY unsupported security feature")
        }
        delegate.setFeature(name, value)
    }
}

class IgnoringSecurityFeatureSaxParserFactory : DelegatingTestSaxParserFactory() {
    override fun setFeature(name: String, value: Boolean) = Unit
}

abstract class DelegatingTestSaxParserFactory : SAXParserFactory() {
    protected val delegate: SAXParserFactory = createPlatformDefaultFactory()

    override fun newSAXParser(): SAXParser = delegate.newSAXParser()

    override fun getFeature(name: String): Boolean = delegate.getFeature(name)

    private companion object {
        const val FACTORY_PROPERTY = "javax.xml.parsers.SAXParserFactory"

        fun createPlatformDefaultFactory(): SAXParserFactory {
            val configuredFactory = System.getProperty(FACTORY_PROPERTY)
            System.clearProperty(FACTORY_PROPERTY)
            return try {
                SAXParserFactory.newInstance()
            } finally {
                if (configuredFactory == null) {
                    System.clearProperty(FACTORY_PROPERTY)
                } else {
                    System.setProperty(FACTORY_PROPERTY, configuredFactory)
                }
            }
        }
    }
}
