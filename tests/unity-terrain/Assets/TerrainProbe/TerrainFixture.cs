using System;
using System.Security.Cryptography;

namespace La64.TerrainProbe
{
    // No Unity dependency: the same fixture is checked on the host and in IL2CPP.
    public static class TerrainFixture
    {
        public const int Resolution = 129;
        public const float Width = 64f;
        public const float Height = 12f;

        // Integer arithmetic followed by an exactly representable binary fraction.
        // Asymmetric hills expose transposed x/z coordinates and lane mistakes.
        public static float[,] Heights(bool flat)
        {
            var values = new float[Resolution, Resolution];
            for (int z = 0; z < Resolution; z++)
                for (int x = 0; x < Resolution; x++)
                {
                    int hillA = Math.Max(0, 48 - Math.Abs(x - 38) - Math.Abs(z - 45));
                    int hillB = Math.Max(0, 31 - Math.Abs(x - 91) - Math.Abs(z - 84));
                    values[z, x] = flat ? 0.125f : (16 + hillA * 2 + hillB) / 256f;
                }
            return values;
        }

        public static float[,,] Alphamaps(int resolution, bool twoLayers)
        {
            var values = new float[resolution, resolution, twoLayers ? 2 : 1];
            for (int z = 0; z < resolution; z++)
                for (int x = 0; x < resolution; x++)
                {
                    float second = ((x / 8 + z / 8) % 2 == 0) ? 0.25f : 0.75f;
                    values[z, x, 0] = twoLayers ? 1f - second : 1f;
                    if (twoLayers) values[z, x, 1] = second;
                }
            return values;
        }

        public static int[] Triangles()
        {
            var result = new int[(Resolution - 1) * (Resolution - 1) * 6];
            int n = 0;
            for (int z = 0; z < Resolution - 1; z++)
                for (int x = 0; x < Resolution - 1; x++)
                {
                    int a = z * Resolution + x;
                    result[n++] = a;
                    result[n++] = a + Resolution;
                    result[n++] = a + 1;
                    result[n++] = a + 1;
                    result[n++] = a + Resolution;
                    result[n++] = a + Resolution + 1;
                }
            return result;
        }

        public static string Hash(float[,] values)
        {
            var bytes = new byte[values.Length * 4];
            int offset = 0;
            foreach (float value in values)
            {
                byte[] word = BitConverter.GetBytes(value);
                if (!BitConverter.IsLittleEndian) Array.Reverse(word);
                Buffer.BlockCopy(word, 0, bytes, offset, 4);
                offset += 4;
            }
            using (var hash = SHA256.Create())
                return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
        }
    }
}
