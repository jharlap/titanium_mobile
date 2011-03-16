/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */
package ti.modules.titanium.database;

import java.lang.reflect.Method;
import java.util.HashMap;

import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiContext;
import org.appcelerator.titanium.util.Log;
import org.appcelerator.titanium.util.TiConfig;

import android.database.AbstractWindowedCursor;
import android.database.Cursor;

@Kroll.proxy
public class TiResultSetProxy extends KrollProxy
{
	private static final String LCAT = "TiResultSet";
	private static final boolean DBG = TiConfig.LOGD;
	
	private static Method isFloat;
	private static Method isLong;
	private static Method isNull;
	private static Class  args[];
	{
		args = new Class[1];
		args[0] = Integer.TYPE;
		
		try {
			isFloat = AbstractWindowedCursor.class.getMethod("isFloat", args);
			isLong  = AbstractWindowedCursor.class.getMethod("isLong",  args);
			isNull  = AbstractWindowedCursor.class.getMethod("isNull",  args);
		} catch (Exception e) {
			isFloat = null;
			isLong  = null;
			isNull  = null;
		}
	}

	protected Cursor rs;
	protected String lastException;
	protected HashMap<String, Integer> columnNames; // workaround case-sensitive matching in Google's implementation

	public TiResultSetProxy(TiContext tiContext, Cursor rs)
	{
		super(tiContext);

		this.rs = rs;
		String[] names = rs.getColumnNames();
		this.columnNames = new HashMap<String, Integer>(names.length);
		for(int i=0; i < names.length; i++) {
			columnNames.put(names[i].toLowerCase(), i);
		}
	}

	@Kroll.method
	public void close() 
	{
		if (rs != null && !rs.isClosed()) {
			if (DBG) {
				Log.d(LCAT, "Closing database cursor");
			}
			rs.close();
		} else {
			Log.w(LCAT, "Calling close on a closed cursor.");
		}

	}

	@Kroll.method
	public Object field(int index) 
	{
		return getField(index);
	}

	@Kroll.method
	public Object getField(int index) 
	{
		Object result = null;
		
		if (rs != null) {
			try {
				result = rs.getString(index);
				if (isFloat != null && rs instanceof AbstractWindowedCursor) {
					AbstractWindowedCursor awc = (AbstractWindowedCursor) rs;
					
					Object arguments[] = new Object[1];
					arguments[0] = new Integer(index);
					try {
						
						if (((Boolean) isFloat.invoke(awc, arguments)).booleanValue())
							result = awc.getDouble(index);
						else if (((Boolean) isLong.invoke(awc, arguments)).booleanValue())
							result = awc.getLong(index);
						else if (((Boolean) isFloat.invoke(awc, arguments)).booleanValue())
							result = null;
					} catch (Exception e) {}
				}
			} catch (Exception e) {
				String msg = "No field at index " + index + ". msg=" + e.getMessage();
				Log.e(LCAT, msg, e);
			}
		}

		return result;
	}

	@Kroll.method
	public Object fieldByName(String fieldName) 
	{
		return getFieldByName(fieldName);
	}

	@Kroll.method
	public Object getFieldByName(String fieldName) 
	{
		Object result = null;
		if (rs != null) {
			try {
				Integer ndx = columnNames.get(fieldName.toLowerCase());
				if (ndx != null)
					result = getField(ndx.intValue());
			} catch (Exception e) {
				String msg = "Field name " + fieldName + " not found. msg=" + e.getMessage();
				Log.e(LCAT, msg);
			}
		}
		
		return result;
	}

	@Kroll.getProperty @Kroll.method
	public int getFieldCount() 
	{
		if (rs != null) {
			try {
				return rs.getColumnCount();
			} catch (Exception e) {
				Log.e(LCAT, "No fields");
			}
		}
		
		return 0;

	}
	
	@Kroll.method
	public String fieldName(int index) 
	{
		return getFieldName(index);
	}
	
	@Kroll.method
	public String getFieldName(int index) 
	{
		if (rs != null) {
			try {
				return rs.getColumnName(index);
			} catch (Exception e) {
				Log.e(LCAT, "No column at index: " + index);
			}
		}
		return null;
	}

	@Kroll.getProperty @Kroll.method
	public int getRowCount() 
	{
		if (rs != null) {
			return rs.getCount();
		}
		
		return 0;
	}

	@Kroll.method
	public boolean isValidRow() 
	{
		boolean valid = false;
		if (rs != null && !rs.isClosed() && !rs.isAfterLast()) {
			valid = true;
		}
		return valid;
	}

	@Kroll.method
	public void next() 
	{
		if(isValidRow()) {
			rs.moveToNext();
		} else {
			Log.w(LCAT, "Ignoring next, row is already invalid.");
		}
	}
}
