// Test fixture: compliant UdonSharp. The comments deliberately mention
// List<T>, async, try/catch, lambda => and System.IO to prove the masker
// keeps them from tripping any rule.
using UdonSharp;
using UnityEngine;
using VRC.SDKBase;

public class GoodExample : UdonSharpBehaviour
{
    [UdonSynced] private int counter;

    // Do not use List<T>, async, try-catch, LINQ or a lambda => here.
    private const string Note = "avoid List<T>, async, try/catch and System.IO";

    public override void Interact()
    {
        if (!Networking.IsOwner(gameObject))
        {
            Networking.SetOwner(Networking.LocalPlayer, gameObject);
        }
        counter++;
        RequestSerialization();
    }

    private void SafeDelayed()
    {
        SendCustomEventDelayedSeconds(nameof(Interact), 1.0f);
    }
}
