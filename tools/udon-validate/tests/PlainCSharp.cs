// Test fixture: plain C#, not UdonSharp. udon-scoped rules must not fire.
using System.Collections.Generic;
using UnityEngine;

public class PlainCSharp : MonoBehaviour
{
    private async void Load()
    {
        var list = new List<int>();
        await System.Threading.Tasks.Task.Yield();
    }
}
