@{
    '135' = @{
        SourceRowNumber = 135
        SourcePath = 'data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv'
        CanonicalSourcePath = 'data/canonical/capital-area-military-benefits.csv'
        SourceCoverage = 'SOURCE_LIMITED'
        ExpectedLabel = 'negative'
        SourceNote = 'P3 review records only POI building 23 versus canonical building 26; no full provider address is present.'
        ObservedBuildingMain = '23'
        CanonicalRow = @{
            업소명 = '이지현미용실'
            시도 = '경기도'
            시군구 = '동두천시'
            소재지도로명주소 = '경기도 동두천시 중앙로295번길 26(생연동)'
            소재지지번주소 = ''
        }
    }
    '136' = @{
        SourceRowNumber = 136
        SourcePath = 'data/canonical/reports/poi-coordinate-review-candidates-20260910-p3.csv'
        CanonicalSourcePath = 'data/canonical/capital-area-military-benefits.csv'
        SourceCoverage = 'SOURCE_LIMITED'
        ExpectedLabel = 'negative'
        SourceNote = 'P3 review records only POI building 904 versus canonical 902 and 2동 104호; no full provider address is present.'
        ObservedBuildingMain = '904'
        CanonicalRow = @{
            업소명 = '인헤어'
            시도 = '경기도'
            시군구 = '동두천시'
            소재지도로명주소 = '경기도 동두천시 삼육사로902, 2동 104호(생연동)'
            소재지지번주소 = ''
        }
    }
    '248' = @{
        SourceRowNumber = 248
        SourcePath = 'data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv'
        CanonicalSourcePath = 'data/canonical/capital-area-military-benefits.csv'
        SourceCoverage = 'FULL_CANDIDATE'
        ExpectedLabel = 'negative'
        SourceNote = 'Final review rejects reported 버섯집초리골 at 초리골길 23 against canonical 초리골길 12.'
        CanonicalRow = @{
            업소명 = '버섯집 초리골'
            시도 = '경기도'
            시군구 = '파주시'
            소재지도로명주소 = '파주시 법원읍 초리골길 12'
            소재지지번주소 = '경기도 파주시 법원읍 법원리 385-12'
        }
        ProviderItem = @{
            title = '버섯집초리골'
            roadAddress = '경기 파주시 법원읍 초리골길 23'
            address = ''
            telephone = ''
            category = ''
            link = ''
            mapx = ''
            mapy = ''
        }
    }
    '339' = @{
        SourceRowNumber = 339
        SourcePath = 'data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv'
        CanonicalSourcePath = 'data/canonical/capital-area-military-benefits.csv'
        SourceCoverage = 'FULL_CANDIDATE'
        ExpectedLabel = 'positive'
        SourceNote = 'Final review approves 거시기닭갈비 덕정본점 at 엄상동길 22-25; provider phone is not preserved as location evidence.'
        CanonicalRow = @{
            업소명 = '거시기닭갈비'
            시도 = '경기도'
            시군구 = '양주시'
            소재지도로명주소 = '경기도 양주시 엄상동길 22-25'
            소재지지번주소 = ''
        }
        ProviderItem = @{
            title = '거시기닭갈비 덕정본점'
            roadAddress = '경기도 양주시 엄상동길 22-25'
            address = '경기도 양주시 고암동 157-6'
            telephone = ''
            category = ''
            link = ''
            mapx = ''
            mapy = ''
        }
    }
    '451' = @{
        SourceRowNumber = 451
        SourcePath = 'data/canonical/reports/poi-coordinate-review-candidates-20260910-final.csv'
        CanonicalSourcePath = 'data/canonical/capital-area-military-benefits.csv'
        SourceCoverage = 'SOURCE_LIMITED'
        ExpectedLabel = 'ambiguous'
        SourceNote = 'Final review holds 짜장마을 because the cited source URL resolves to a search for 짜장단가든, so it does not establish a trustworthy provider candidate.'
        CanonicalRow = @{
            업소명 = '짜장마을'
            시도 = '경기도'
            시군구 = '파주시'
            소재지도로명주소 = '파주시 파주읍 술이홀로 463'
            소재지지번주소 = '경기도 파주시 파주읍 연풍리 279-9'
        }
    }
}
