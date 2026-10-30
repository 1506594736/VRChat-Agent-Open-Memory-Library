// Test fixture: deliberately violates Udon constraints. Not usable code.
using System;
using System.IO;
using System.Collections.Generic;
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;

public class BadExample : UdonSharpBehaviour
{
    [UdonSynced] public int counter;
    [UdonSynced] private int[] bigArray = new int[16];

    private async void BadAsync()
    {
        await System.Threading.Tasks.Task.Delay(100);
    }

    private void BadTry()
    {
        try { Debug.Log("x"); }
        catch (Exception e) { Debug.Log(e.Message); }
    }

    private void BadCoroutine()
    {
        StartCoroutine(FakeCoroutine());
    }

    private void BadListener()
    {
        var button = GetComponent<UnityEngine.UI.Button>();
        button.onClick.AddListener(BadTry);
    }

    private void BadIO()
    {
        File.ReadAllText("somepath");
    }

    private void BadLinq()
    {
        var list = new List<int> { 1, 2, 3 };
        var even = list.FindAll(x => x % 2 == 0);
    }

    private void BadMultiDim()
    {
        int[,] grid = new int[4, 4];
    }

    private System.Collections.IEnumerator FakeCoroutine()
    {
        yield return null;
    }
}
