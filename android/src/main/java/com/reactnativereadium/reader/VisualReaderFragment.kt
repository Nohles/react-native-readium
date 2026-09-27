/*
 * Copyright 2021 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package com.reactnativereadium.reader

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import androidx.fragment.app.Fragment
import com.reactnativereadium.R
import com.reactnativereadium.databinding.FragmentReaderBinding
import com.reactnativereadium.utils.clearPadding
import com.reactnativereadium.utils.hideSystemUi
import com.reactnativereadium.utils.padSystemUi
import com.reactnativereadium.utils.showSystemUi

/*
 * Adds fullscreen support to the BaseReaderFragment
 *
 * Note: this used to also own a `PositionLabelManager` overlay showing "n / N".
 * It was created and then immediately set to `GONE`, because host apps render
 * their own reader chrome (mirroring `positionLabel.isHidden = true` in
 * ios/Reader/Common/ReaderViewController.swift:96). The label, its position
 * count lookup, and the per-theme colour plumbing were all dead weight, so the
 * subsystem was removed rather than left half-wired.
 */
abstract class VisualReaderFragment : BaseReaderFragment() {

    private lateinit var navigatorFragment: Fragment

    private var _binding: FragmentReaderBinding? = null
    val binding get() = _binding!!

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        _binding = FragmentReaderBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        navigatorFragment = navigator as Fragment

        childFragmentManager.addOnBackStackChangedListener {
            updateSystemUiVisibility()
        }
        binding.fragmentReaderContainer.setOnApplyWindowInsetsListener { container, insets ->
            updateSystemUiPadding(container, insets)
            insets
        }
    }

    override fun onDestroyView() {
        _binding = null
        super.onDestroyView()
    }

    fun updateSystemUiVisibility() {
        if (navigatorFragment.isHidden)
            requireActivity().showSystemUi()
        else
            requireActivity().hideSystemUi()

        requireView().requestApplyInsets()
    }

    private fun updateSystemUiPadding(container: View, insets: WindowInsets) {
        if (navigatorFragment.isHidden) {
            container.padSystemUi(insets, requireActivity())
        } else {
            container.clearPadding()
        }
    }
}
