using System;

namespace Machine.Specifications
{
  public static class Catch
  {
    public static Exception Exception(Action throwingAction)
    {
      try
      {
        throwingAction();
      }
      catch (Exception exception)
      {
        return exception;
      }

      return null;
    }

    public static Exception Exception<T>(Func<T> throwingFunc)
    {
      try
      {
        throwingFunc();
      }
      catch (Exception exception)
      {
        return exception;
      }

      return null;
    }
  }
}
