using System;
using System.Linq;
using La64.TerrainProbe;

static void Check(bool condition, string why)
{
    if (!condition) throw new Exception(why);
}
var flat = TerrainFixture.Heights(true);
var hills = TerrainFixture.Heights(false);
Check(TerrainFixture.Hash(flat) == "7c935cec20125247b35efaa5ce3ba30e83b37ec2a3894d5621e8ee7eab7ccc9c", "flat hash differs from independent Python fixture");
Check(TerrainFixture.Hash(hills) == "f9ef55c09dba009ac22909e19adf3d1df6124873aee6c8086a6254be1244044e", "hills hash differs from independent Python fixture");
Check(hills[45, 38] == 112f / 256f, "first peak position/height");
Check(hills[84, 91] == 47f / 256f, "second peak position/height");
Check(hills[38, 45] != hills[45, 38], "fixture must expose coordinate transposition");
foreach (float h in hills) Check(h >= 0f && h <= 1f && float.IsFinite(h), "invalid height");
int n = TerrainFixture.Resolution;
int[] triangles = TerrainFixture.Triangles();
Check(triangles.Length == (n - 1) * (n - 1) * 6, "triangle count");
var referenced = new bool[n * n];
for (int i = 0; i < triangles.Length; i += 3)
{
    int a = triangles[i], b = triangles[i + 1], c = triangles[i + 2];
    foreach (int v in new[] { a, b, c }) { Check(v >= 0 && v < n * n, "index bounds"); referenced[v] = true; }
    // Cross(B-A,C-A).y in x/z plane must point upward for backface culling.
    int up = (b / n - a / n) * (c % n - a % n) - (b % n - a % n) * (c / n - a / n);
    Check(up == 1, "triangle winding or degeneracy");
}
Check(referenced.All(v => v), "unreferenced vertex");
foreach (bool blend in new[] { false, true })
{
    var alpha = TerrainFixture.Alphamaps(64, blend);
    for (int z = 0; z < 64; z++)
        for (int x = 0; x < 64; x++)
        {
            float sum = 0;
            for (int l = 0; l < alpha.GetLength(2); l++) { float v = alpha[z, x, l]; Check(v >= 0f && v <= 1f, "alpha bounds"); sum += v; }
            Check(sum == 1f, "alpha normalization");
        }
}
Console.WriteLine("PASS: independent fixture hashes, asymmetric peaks, height range, all 32768 triangle windings/indices, full vertex coverage, 8192 alpha sums.");
