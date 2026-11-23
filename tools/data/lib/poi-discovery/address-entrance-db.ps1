Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
} catch {
}

if (-not ('Milimap.EntranceDb.EntranceDbMatcher' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace Milimap.EntranceDb {
    public sealed class AccumData {
        public double SumX;
        public double SumY;
        public int Count;
        public string District;
        public string RoadName;
    }

    public sealed class IndexResult {
        public Dictionary<string, AccumData> JusoIndex;
        public Dictionary<string, AccumData> RoadIndex;
    }

    public static class EntranceDbMatcher {
        private const double A = 6378137.0;
        private const double F = 1.0 / 298.257222101; // GRS80
        private const double K0 = 0.9996;
        private const double Fe = 1000000.0;
        private const double Fn = 2000000.0;
        private static readonly double Lat0 = 38.0 * Math.PI / 180.0;
        private static readonly double Lon0 = 127.5 * Math.PI / 180.0;

        private static readonly double E2 = F * (2.0 - F);
        private static readonly double Ep2 = E2 / (1.0 - E2);
        private static readonly double M0 = ComputeMeridianArc(Lat0);

        private static double ComputeMeridianArc(double phi) {
            double e4 = E2 * E2;
            double e6 = e4 * E2;
            return A * (
                (1.0 - E2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * phi
                - (3.0 * E2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * Math.Sin(2.0 * phi)
                + (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * Math.Sin(4.0 * phi)
                - (35.0 * e6 / 3072.0) * Math.Sin(6.0 * phi)
            );
        }

        public static double[] UtmKToWgs84Pair(double x, double y) {
            double e4 = E2 * E2;
            double e6 = e4 * E2;
            double M = M0 + (y - Fn) / K0;
            double mu = M / (A * (1.0 - E2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0));
            double sqrt1MinusE2 = Math.Sqrt(1.0 - E2);
            double e1 = (1.0 - sqrt1MinusE2) / (1.0 + sqrt1MinusE2);
            double e1_2 = e1 * e1;
            double e1_3 = e1_2 * e1;
            double e1_4 = e1_2 * e1_2;

            double phi1 = mu
                + (3.0 * e1 / 2.0 - 27.0 * e1_3 / 32.0) * Math.Sin(2.0 * mu)
                + (21.0 * e1_2 / 16.0 - 55.0 * e1_4 / 32.0) * Math.Sin(4.0 * mu)
                + (151.0 * e1_3 / 96.0) * Math.Sin(6.0 * mu)
                + (1097.0 * e1_4 / 512.0) * Math.Sin(8.0 * mu);

            double sinP = Math.Sin(phi1);
            double cosP = Math.Cos(phi1);
            double tanP = Math.Tan(phi1);
            double C1 = Ep2 * cosP * cosP;
            double T1 = tanP * tanP;
            double denom = 1.0 - E2 * sinP * sinP;
            double N1 = A / Math.Sqrt(denom);
            double R1 = A * (1.0 - E2) / (denom * Math.Sqrt(denom));
            double D = (x - Fe) / (N1 * K0);

            double D2 = D * D;
            double D3 = D2 * D;
            double D4 = D3 * D;
            double D5 = D4 * D;
            double D6 = D5 * D;

            double lat = phi1 - (N1 * tanP / R1) * (
                D2 / 2.0
                - (5.0 + 3.0 * T1 + 10.0 * C1 - 4.0 * C1 * C1 - 9.0 * Ep2) * D4 / 24.0
                + (61.0 + 90.0 * T1 + 298.0 * C1 + 45.0 * T1 * T1 - 252.0 * Ep2 - 3.0 * C1 * C1) * D6 / 720.0
            );
            double lon = Lon0 + (
                D
                - (1.0 + 2.0 * T1 + C1) * D3 / 6.0
                + (5.0 - 2.0 * C1 + 28.0 * T1 - 3.0 * C1 * C1 + 8.0 * Ep2 + 24.0 * T1 * T1) * D5 / 120.0
            ) / cosP;

            return new[] { lat * 180.0 / Math.PI, lon * 180.0 / Math.PI };
        }

        private static string NormCompact(string s) {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace(" ", "").Replace("\t", "").Trim().ToLowerInvariant();
        }

        private static string CleanInt(string s) {
            if (string.IsNullOrWhiteSpace(s)) return "0";
            int v;
            return int.TryParse(s.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out v)
                ? v.ToString(CultureInfo.InvariantCulture)
                : "0";
        }

        public static string MakeJusoKey(string rnMgtSn, string udrt, string mnnm, string slno) {
            string safeRn = string.IsNullOrWhiteSpace(rnMgtSn) ? "" : rnMgtSn.Trim();
            string safeUdrt = string.IsNullOrWhiteSpace(udrt) ? "0" : udrt.Trim();
            return safeRn + "|" + safeUdrt + "|" + CleanInt(mnnm) + "|" + CleanInt(slno);
        }

        public static string MakeRoadKey(string sigungu, string roadName, string udrt, string mnnm, string slno) {
            string safeUdrt = string.IsNullOrWhiteSpace(udrt) ? "0" : udrt.Trim();
            return NormCompact(sigungu) + "|" + NormCompact(roadName) + "|" + safeUdrt + "|" + CleanInt(mnnm) + "|" + CleanInt(slno);
        }

        public static IndexResult BuildIndex(
            string[] entrcFiles,
            string[] neededJusoArray,
            string[] neededRoadArray,
            string encodingName
        ) {
            var neededJuso = new HashSet<string>(StringComparer.Ordinal);
            if (neededJusoArray != null) {
                foreach (string k in neededJusoArray) {
                    if (!string.IsNullOrWhiteSpace(k)) neededJuso.Add(k);
                }
            }
            var neededRoad = new HashSet<string>(StringComparer.Ordinal);
            if (neededRoadArray != null) {
                foreach (string k in neededRoadArray) {
                    if (!string.IsNullOrWhiteSpace(k)) neededRoad.Add(k);
                }
            }

            var jusoIndex = new Dictionary<string, AccumData>(StringComparer.Ordinal);
            var roadIndex = new Dictionary<string, AccumData>(StringComparer.Ordinal);
            if (neededJuso.Count == 0 && neededRoad.Count == 0) {
                return new IndexResult { JusoIndex = jusoIndex, RoadIndex = roadIndex };
            }

            Encoding enc = string.Equals(encodingName, "UTF8", StringComparison.OrdinalIgnoreCase)
                ? new UTF8Encoding(false)
                : Encoding.GetEncoding(949);

            foreach (string path in entrcFiles) {
                if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) continue;
                using (var sr = new StreamReader(path, enc)) {
                    string line;
                    while ((line = sr.ReadLine()) != null) {
                        string[] cols = line.Split('|');
                        if (cols.Length < 18) continue;
                        double x, y;
                        if (!double.TryParse(cols[16], NumberStyles.Float, CultureInfo.InvariantCulture, out x)) continue;
                        if (!double.TryParse(cols[17], NumberStyles.Float, CultureInfo.InvariantCulture, out y)) continue;
                        if (x <= 0 || y <= 0) continue;

                        if (neededJuso.Count > 0) {
                            string jk = MakeJusoKey(cols[6], cols[8], cols[9], cols[10]);
                            if (neededJuso.Contains(jk)) {
                                AccumData acc;
                                if (!jusoIndex.TryGetValue(jk, out acc)) {
                                    acc = new AccumData { District = cols[4].Trim(), RoadName = cols[7].Trim() };
                                    jusoIndex[jk] = acc;
                                }
                                acc.SumX += x;
                                acc.SumY += y;
                                acc.Count++;
                            }
                        }

                        if (neededRoad.Count > 0) {
                            string rk1 = MakeRoadKey(cols[4], cols[7], cols[8], cols[9], cols[10]);
                            string sig = cols[4].Trim();
                            int spIdx = sig.IndexOf(' ');
                            string rkLast = spIdx >= 0 ? MakeRoadKey(sig.Substring(spIdx + 1), cols[7], cols[8], cols[9], cols[10]) : null;
                            string rkFirst = spIdx >= 0 ? MakeRoadKey(sig.Substring(0, spIdx), cols[7], cols[8], cols[9], cols[10]) : null;

                            foreach (string rk in new[] { rk1, rkLast, rkFirst }) {
                                if (rk != null && neededRoad.Contains(rk)) {
                                    AccumData acc;
                                    if (!roadIndex.TryGetValue(rk, out acc)) {
                                        acc = new AccumData { District = cols[4].Trim(), RoadName = cols[7].Trim() };
                                        roadIndex[rk] = acc;
                                    }
                                    acc.SumX += x;
                                    acc.SumY += y;
                                    acc.Count++;
                                }
                            }
                        }
                    }
                }
            }

            return new IndexResult { JusoIndex = jusoIndex, RoadIndex = roadIndex };
        }
    }
}
'@
}

function ConvertFrom-Utmk5179ToWgs84 {
    param(
        [Parameter(Mandatory)][double]$X,
        [Parameter(Mandatory)][double]$Y
    )

    $pair = [Milimap.EntranceDb.EntranceDbMatcher]::UtmKToWgs84Pair($X, $Y)
    return [pscustomobject][ordered]@{
        Latitude = [Math]::Round([double]$pair[0], 7)
        Longitude = [Math]::Round([double]$pair[1], 7)
    }
}

function Get-AddressEntranceJusoKey {
    param(
        [AllowNull()][string]$RnMgtSn = '',
        [AllowNull()][string]$UndergroundYn = '0',
        [AllowNull()][string]$BuildingMain = '0',
        [AllowNull()][string]$BuildingSub = '0'
    )

    return [Milimap.EntranceDb.EntranceDbMatcher]::MakeJusoKey($RnMgtSn, $UndergroundYn, $BuildingMain, $BuildingSub)
}

function Get-AddressEntranceRoadKey {
    param(
        [AllowNull()][string]$Sigungu = '',
        [AllowNull()][string]$RoadName = '',
        [AllowNull()][string]$UndergroundYn = '0',
        [AllowNull()][string]$BuildingMain = '0',
        [AllowNull()][string]$BuildingSub = '0'
    )

    return [Milimap.EntranceDb.EntranceDbMatcher]::MakeRoadKey($Sigungu, $RoadName, $UndergroundYn, $BuildingMain, $BuildingSub)
}

function Import-AddressEntranceDbIndex {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [AllowEmptyCollection()][string[]]$NeededJusoKeys = @(),
        [AllowEmptyCollection()][string[]]$NeededRoadKeys = @(),
        [ValidateSet('CP949', 'UTF8')]
        [string]$EncodingName = 'CP949'
    )

    return [Milimap.EntranceDb.EntranceDbMatcher]::BuildIndex($Paths, $NeededJusoKeys, $NeededRoadKeys, $EncodingName)
}

function Resolve-AddressEntranceCoordinate {
    param(
        [Parameter(Mandatory)]$Index,
        [AllowNull()][string]$RnMgtSn = '',
        [AllowNull()][string]$UndergroundYn = '0',
        [AllowEmptyCollection()][string[]]$SigunguCandidates = @(),
        [AllowNull()][string]$RoadName = '',
        [AllowNull()][string]$BuildingMain = '0',
        [AllowNull()][string]$BuildingSub = '0'
    )

    $matchedAcc = $null
    $matchType = 'UNMATCHED'

    if (-not [string]::IsNullOrWhiteSpace($RnMgtSn)) {
        $jKey = Get-AddressEntranceJusoKey -RnMgtSn $RnMgtSn -UndergroundYn $UndergroundYn -BuildingMain $BuildingMain -BuildingSub $BuildingSub
        $acc = $null
        if ($Index.JusoIndex.TryGetValue($jKey, [ref]$acc)) {
            $matchedAcc = $acc
            $matchType = 'ENTRC_JUSO_EXACT'
        }
    }

    if ($null -eq $matchedAcc -and -not [string]::IsNullOrWhiteSpace($RoadName) -and -not [string]::IsNullOrWhiteSpace($BuildingMain)) {
        foreach ($sig in @($SigunguCandidates)) {
            if ([string]::IsNullOrWhiteSpace($sig)) { continue }
            $rKey = Get-AddressEntranceRoadKey -Sigungu $sig -RoadName $RoadName -UndergroundYn $UndergroundYn -BuildingMain $BuildingMain -BuildingSub $BuildingSub
            $acc = $null
            if ($Index.RoadIndex.TryGetValue($rKey, [ref]$acc)) {
                $matchedAcc = $acc
                $matchType = 'ENTRC_ROAD_EXACT'
                break
            }
        }
    }

    if ($null -ne $matchedAcc -and $matchedAcc.Count -gt 0) {
        $avgX = $matchedAcc.SumX / [double]$matchedAcc.Count
        $avgY = $matchedAcc.SumY / [double]$matchedAcc.Count
        $coords = ConvertFrom-Utmk5179ToWgs84 -X $avgX -Y $avgY
        return [pscustomobject][ordered]@{
            Found = $true
            MatchType = $matchType
            Latitude = $coords.Latitude
            Longitude = $coords.Longitude
            EntranceCount = [int]$matchedAcc.Count
            EntrcDistrict = [string]$matchedAcc.District
            EntrcRoadName = [string]$matchedAcc.RoadName
            CoordinateSource = '행정안전부 위치정보요약DB(2026-10)'
            CoordinateSourceUrl = 'https://business.juso.go.kr'
        }
    }

    return [pscustomobject][ordered]@{
        Found = $false
        MatchType = 'UNMATCHED'
        Latitude = $null
        Longitude = $null
        EntranceCount = 0
        EntrcDistrict = ''
        EntrcRoadName = ''
        CoordinateSource = ''
        CoordinateSourceUrl = ''
    }
}
